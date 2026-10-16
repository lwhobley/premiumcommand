-- Meeting notes.
--
-- An administrator records what was discussed in a meeting. The meeting-notes-ai Edge Function
-- asks Claude which event the meeting was about and what should change because of it. Nothing
-- changes until an administrator reviews the proposal and applies it with apply_meeting_note,
-- which links the note to the event and makes every accepted change in one transaction.
--
-- Drafts and proposals are visible to administrators only. Once applied, a note's summary is
-- part of the event's record, so every member of the venue can read it on the event.

create table public.meeting_notes (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  event_id uuid,
  title text not null default '' check (char_length(title) <= 200),
  body text not null check (length(trim(body)) > 0 and char_length(body) <= 20000),
  meeting_at timestamptz,
  status text not null default 'draft'
    check (status in ('draft', 'analyzed', 'applied', 'dismissed')),
  -- The latest proposal from the Edge Function. Replaced on every analysis.
  analysis jsonb,
  -- Set by apply_meeting_note only.
  summary text not null default '',
  key_details text[] not null default '{}',
  applied_actions jsonb not null default '[]'::jsonb,
  applied_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meeting_notes_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete set null (event_id)
);
create index meeting_notes_venue_created_idx on public.meeting_notes(venue_id, created_at desc);
create index meeting_notes_event_idx on public.meeting_notes(event_id) where event_id is not null;

alter table public.meeting_notes enable row level security;

create policy meeting_notes_read on public.meeting_notes for select to authenticated
  using (
    public.has_permission(venue_id, 'manage_configuration')
    or (status = 'applied' and public.is_venue_member(venue_id))
  );
create policy meeting_notes_insert on public.meeting_notes for insert to authenticated
  with check (
    public.has_permission(venue_id, 'manage_configuration')
    and status = 'draft' and created_by = (select auth.uid())
  );
-- An applied note is part of the event's history and cannot be edited or removed.
create policy meeting_notes_update on public.meeting_notes for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration') and status <> 'applied')
  with check (
    public.has_permission(venue_id, 'manage_configuration')
    and status in ('draft', 'analyzed', 'dismissed')
  );
create policy meeting_notes_delete on public.meeting_notes for delete to authenticated
  using (public.has_permission(venue_id, 'manage_configuration') and status <> 'applied');

-- The applied fields are written only by apply_meeting_note.
revoke all on public.meeting_notes from anon;
revoke insert, update on public.meeting_notes from authenticated;
grant insert (venue_id, event_id, title, body, meeting_at)
  on public.meeting_notes to authenticated;
grant update (event_id, title, body, meeting_at, status, analysis, updated_at)
  on public.meeting_notes to authenticated;

-- Applies a reviewed meeting note to one event.
--
-- p_actions is the list of changes the administrator accepted. Each entry has a "type":
--   update_event        field (name | guaranteed_guests | manager_name | service_start |
--                       service_end), value
--   append_event_notes  text
--   add_task            department, title, is_required, due_at (optional)
--   post_announcement   body (notifies everyone rostered on the event)
--   add_menu_item       name, course, dietary_tags, allergens
--   update_suite        assignment_id, field (dietary_notes | special_instructions |
--                       guest_contact), value
-- Every value is checked here. A bad entry fails the whole call and nothing is changed.
create or replace function public.apply_meeting_note(
  p_note uuid,
  p_event uuid,
  p_summary text,
  p_key_details text[],
  p_actions jsonb
)
returns public.meeting_notes
language plpgsql security definer set search_path = public
as $$
declare
  n meeting_notes%rowtype;
  ev events%rowtype;
  original events%rowtype;
  a jsonb;
  kind text;
  field text;
  val text;
  dept text;
  stamp timestamptz;
  assignment uuid;
  actions jsonb := coalesce(p_actions, '[]'::jsonb);
  types text[] := '{}';
begin
  select * into n from meeting_notes where id = p_note for update;
  if not found then
    raise exception 'Meeting note not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(n.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can apply meeting notes' using errcode = '42501';
  end if;
  if n.status = 'applied' then
    raise exception 'This meeting note has already been applied' using errcode = '23514';
  end if;

  select * into ev from events where id = p_event and venue_id = n.venue_id for update;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  original := ev;

  if jsonb_typeof(actions) <> 'array' then
    raise exception 'Changes must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(actions) > 50 then
    raise exception 'Apply at most 50 changes at once' using errcode = '22023';
  end if;
  if jsonb_array_length(actions) > 0 then
    if ev.status in ('closed', 'cancelled') then
      raise exception 'A % event cannot be changed. Apply the note without changes to keep it on record.',
        ev.status using errcode = '23514';
    end if;
    if not public.has_permission(n.venue_id, 'manage_events') then
      raise exception 'Changing an event needs event management permission' using errcode = '42501';
    end if;
  end if;

  for a in select value from jsonb_array_elements(actions) loop
    kind := a ->> 'type';
    types := types || coalesce(kind, 'unknown');
    case kind
      when 'update_event' then
        field := a ->> 'field';
        val := trim(coalesce(a ->> 'value', ''));
        case field
          when 'name' then
            if val = '' or char_length(val) > 200 then
              raise exception 'Event name must be 1 to 200 characters' using errcode = '22023';
            end if;
            ev.name := val;
          when 'manager_name' then
            if char_length(val) > 200 then
              raise exception 'Manager name is too long' using errcode = '22023';
            end if;
            ev.manager_name := val;
          when 'guaranteed_guests' then
            if val !~ '^[0-9]{1,6}$' then
              raise exception 'Guaranteed guests must be a whole number' using errcode = '22023';
            end if;
            ev.guaranteed_guests := val::integer;
          when 'service_start', 'service_end' then
            begin
              stamp := val::timestamptz;
            exception when others then
              raise exception 'Service time "%" is not a valid date and time', val using errcode = '22023';
            end;
            if field = 'service_start' then ev.service_start := stamp; else ev.service_end := stamp; end if;
          else
            raise exception 'Unknown event field "%"', field using errcode = '22023';
        end case;

      when 'append_event_notes' then
        val := trim(coalesce(a ->> 'text', ''));
        if val = '' or char_length(val) > 4000 then
          raise exception 'Event notes must be 1 to 4000 characters' using errcode = '22023';
        end if;
        ev.notes := case when ev.notes = '' then val else ev.notes || E'\n\n' || val end;

      when 'add_task' then
        dept := a ->> 'department';
        val := trim(coalesce(a ->> 'title', ''));
        if dept is null or dept not in ('suites', 'banquets', 'culinary', 'beverage', 'lounge', 'operations') then
          raise exception 'Unknown department "%"', dept using errcode = '22023';
        end if;
        if val = '' or char_length(val) > 200 then
          raise exception 'Task title must be 1 to 200 characters' using errcode = '22023';
        end if;
        stamp := null;
        if coalesce(a ->> 'due_at', '') <> '' then
          begin
            stamp := (a ->> 'due_at')::timestamptz;
          exception when others then
            raise exception 'Task due time "%" is not a valid date and time', a ->> 'due_at'
              using errcode = '22023';
          end;
        end if;
        insert into event_tasks (venue_id, event_id, department, title, is_required, due_at)
        values (ev.venue_id, ev.id, dept, val,
                coalesce((a ->> 'is_required')::boolean, false), stamp);

      when 'post_announcement' then
        val := trim(coalesce(a ->> 'body', ''));
        if val = '' or char_length(val) > 2000 then
          raise exception 'Announcement must be 1 to 2000 characters' using errcode = '22023';
        end if;
        insert into event_announcements (venue_id, event_id, body, author_id)
        values (ev.venue_id, ev.id, val, auth.uid());

      when 'add_menu_item' then
        val := trim(coalesce(a ->> 'name', ''));
        if val = '' or char_length(val) > 200 then
          raise exception 'Menu item name must be 1 to 200 characters' using errcode = '22023';
        end if;
        insert into event_menu_items (venue_id, event_id, name, course, dietary_tags, allergens)
        values (
          ev.venue_id, ev.id, val,
          left(trim(coalesce(a ->> 'course', '')), 100),
          coalesce(array(
            select left(trim(t), 50)
            from jsonb_array_elements_text(
              case when jsonb_typeof(a -> 'dietary_tags') = 'array' then a -> 'dietary_tags' else '[]'::jsonb end
            ) t
            where trim(t) <> ''
          ), '{}'),
          left(trim(coalesce(a ->> 'allergens', '')), 500)
        );

      when 'update_suite' then
        field := a ->> 'field';
        val := trim(coalesce(a ->> 'value', ''));
        begin
          assignment := (a ->> 'assignment_id')::uuid;
        exception when others then
          raise exception 'Unknown suite assignment' using errcode = '22023';
        end;
        if field is null or field not in ('dietary_notes', 'special_instructions', 'guest_contact') then
          raise exception 'Unknown suite field "%"', field using errcode = '22023';
        end if;
        if char_length(val) > 2000 then
          raise exception 'Suite detail is too long' using errcode = '22023';
        end if;
        update suite_event_assignments
           set dietary_notes = case when field = 'dietary_notes' then val else dietary_notes end,
               special_instructions = case when field = 'special_instructions' then val else special_instructions end,
               guest_contact = case when field = 'guest_contact' then val else guest_contact end,
               version = version + 1,
               updated_at = now()
         where id = assignment and event_id = ev.id and venue_id = ev.venue_id;
        if not found then
          raise exception 'That suite is not assigned to this event' using errcode = 'P0002';
        end if;

      else
        raise exception 'Unknown change type "%"', kind using errcode = '22023';
    end case;
  end loop;

  if ev is distinct from original then
    -- service_end > service_start is checked by the events table constraint.
    update events
       set name = ev.name,
           guaranteed_guests = ev.guaranteed_guests,
           manager_name = ev.manager_name,
           service_start = ev.service_start,
           service_end = ev.service_end,
           notes = ev.notes,
           version = version + 1,
           updated_at = now()
     where id = ev.id;
  end if;

  update meeting_notes
     set status = 'applied',
         event_id = ev.id,
         summary = left(trim(coalesce(p_summary, '')), 4000),
         key_details = coalesce(array(
           select left(trim(d), 500) from unnest(coalesce(p_key_details, '{}')) d where trim(d) <> ''
         ), '{}'),
         applied_actions = actions,
         applied_by = auth.uid(),
         applied_at = now(),
         updated_at = now()
   where id = n.id
  returning * into n;

  -- The audit entry records what kind of changes were made, not the free text.
  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (n.venue_id, 'meeting_note.applied', 'meeting_note', n.id,
          jsonb_build_object('event_id', ev.id, 'change_types', to_jsonb(types)));

  return n;
end;
$$;

revoke execute on function public.apply_meeting_note(uuid, uuid, text, text[], jsonb) from public, anon;
grant execute on function public.apply_meeting_note(uuid, uuid, text, text[], jsonb) to authenticated;
