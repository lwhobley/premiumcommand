-- Prevent direct inserts from skipping state machines or fabricating sign-offs.

alter table public.beo_revisions add column affected_departments text[] not null default '{}';
update public.beo_revisions
   set affected_departments = array(
     select jsonb_array_elements_text(coalesce(content -> 'departments', '[]'::jsonb))
   )
 where status = 'approved';

alter policy event_tasks_insert on public.event_tasks
  with check (
    public.has_permission(venue_id, 'manage_events')
    and status = 'not_started' and completed_at is null and completed_by is null
    and needs_review = false and review_reason = ''
  );
revoke update (status, completed_at, completed_by, updated_at)
  on public.event_tasks from authenticated, anon;

alter policy suite_assignments_insert on public.suite_event_assignments
  with check (
    public.has_permission(venue_id, 'manage_events')
    and state = 'not_started' and version = 1
  );
alter policy timeline_insert on public.banquet_timeline_items
  with check (
    public.has_permission(venue_id, 'manage_banquets')
    and status = 'scheduled' and actual_completion is null and version = 1
  );
alter policy batches_insert on public.culinary_batches
  with check (
    public.has_permission(venue_id, 'view_culinary')
    and state = 'planned' and version = 1
    and ready_at is null and collected_at is null
    and delivered_at is null and received_at is null
    and received_by = ''
  );

alter policy events_insert on public.events
  with check (public.has_permission(venue_id, 'manage_events')
    and status = 'draft' and created_by = (select auth.uid()));
alter policy briefings_write on public.event_briefings
  with check (public.has_permission(venue_id, 'deploy_staff')
    and created_by = (select auth.uid()));

-- A department member or event manager may acknowledge that department's BEO.
create or replace function public.acknowledge_beo_revision(p_revision uuid, p_department text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  r public.beo_revisions%rowtype;
begin
  select * into r from public.beo_revisions where id = p_revision;
  if not found then raise exception 'Revision not found' using errcode = 'P0002'; end if;
  if not public.is_venue_member(r.venue_id) or
     not public.has_permission(r.venue_id, 'update_tasks') or
     not (public.in_department(r.venue_id, p_department) or
          public.has_permission(r.venue_id, 'manage_events')) then
    raise exception 'Not authorized to acknowledge this department' using errcode = '42501';
  end if;
  if r.status <> 'approved' then
    raise exception 'Only approved revisions can be acknowledged';
  end if;
  if not p_department = any(coalesce(r.affected_departments, '{}'::text[])) then
    raise exception 'Department is not affected by this revision' using errcode = '22023';
  end if;

  insert into public.beo_acknowledgments (revision_id, venue_id, department, user_id)
  values (r.id, r.venue_id, p_department, auth.uid())
  on conflict do nothing;

  update public.event_tasks t
     set needs_review = false, review_reason = '', updated_at = now()
   where t.event_id = (select event_id from public.beo_documents where id = r.beo_id)
     and t.department = p_department and t.needs_review;
  return true;
end;
$$;

-- Configuration managers can maintain items on their venue's templates.
-- Shared checklist items remain read-only, and an item cannot be moved to a
-- different template after an inspection has used it.
create index if not exists checklist_items_template_idx
  on public.checklist_items(template_id);
grant insert, delete on public.checklist_items to authenticated;
revoke update on public.checklist_items from authenticated, anon;
grant update (position, label, response_type, requires_manager_approval, department)
  on public.checklist_items to authenticated;
create policy checklist_items_insert on public.checklist_items
  for insert to authenticated with check (exists (
    select 1 from public.checklist_templates t
    where t.id = template_id and t.venue_id is not null
      and public.has_permission(t.venue_id, 'manage_configuration')
  ));
create policy checklist_items_update on public.checklist_items
  for update to authenticated
  using (exists (
    select 1 from public.checklist_templates t
    where t.id = template_id and t.venue_id is not null
      and public.has_permission(t.venue_id, 'manage_configuration')
  ))
  with check (exists (
    select 1 from public.checklist_templates t
    where t.id = template_id and t.venue_id is not null
      and public.has_permission(t.venue_id, 'manage_configuration')
  ));
create policy checklist_items_delete on public.checklist_items
  for delete to authenticated using (exists (
    select 1 from public.checklist_templates t
    where t.id = template_id and t.venue_id is not null
      and public.has_permission(t.venue_id, 'manage_configuration')
  ));

-- Record precisely which departments need review. Global BEO fields affect all
-- listed departments; menu and beverage changes affect their respective teams.
create or replace function public.approve_beo_revision(p_revision uuid)
returns public.beo_revisions
language plpgsql security definer set search_path = public
as $$
declare
  r public.beo_revisions%rowtype;
  doc public.beo_documents%rowtype;
  previous public.beo_revisions%rowtype;
  old_departments text[];
  new_departments text[];
  affected text[];
  global_change boolean;
begin
  select * into r from public.beo_revisions where id = p_revision for update;
  if not found then raise exception 'Revision not found' using errcode = 'P0002'; end if;
  if not public.has_permission(r.venue_id, 'approve_beo') then
    raise exception 'Only directors can approve BEOs' using errcode = '42501';
  end if;
  if r.status <> 'draft' then raise exception 'Only draft revisions can be approved'; end if;

  select * into doc from public.beo_documents where id = r.beo_id for update;
  if r.revision_no <> (select max(revision_no) from public.beo_revisions where beo_id = doc.id) then
    raise exception 'Approve the latest BEO draft' using errcode = '40001';
  end if;
  if doc.current_revision_id is not null then
    select * into previous from public.beo_revisions where id = doc.current_revision_id;
  end if;
  new_departments := array(
    select jsonb_array_elements_text(coalesce(r.content -> 'departments', '[]'::jsonb))
  );
  if previous.id is null then
    affected := new_departments;
  else
    old_departments := array(
      select jsonb_array_elements_text(coalesce(previous.content -> 'departments', '[]'::jsonb))
    );
    global_change := (r.content - 'departments' - 'menu' - 'dietary' - 'beverage' - 'equipment')
      is distinct from (previous.content - 'departments' - 'menu' - 'dietary' - 'beverage' - 'equipment');
    select coalesce(array_agg(distinct department), '{}'::text[]) into affected
      from unnest(old_departments || new_departments) as d(department)
     where global_change
        or (department = any(old_departments)) <> (department = any(new_departments))
        or (department = 'culinary' and
            ((r.content -> 'menu') is distinct from (previous.content -> 'menu') or
             (r.content -> 'dietary') is distinct from (previous.content -> 'dietary')))
        or (department = 'beverage' and
            (r.content -> 'beverage') is distinct from (previous.content -> 'beverage'))
        or (department = 'operations' and
            (r.content -> 'equipment') is distinct from (previous.content -> 'equipment'));
  end if;
  update public.beo_revisions set status = 'superseded'
   where beo_id = doc.id and status = 'approved';
  update public.beo_revisions
     set status = 'approved', approved_by = auth.uid(), approved_at = now(),
         affected_departments = coalesce(affected, '{}'::text[])
   where id = r.id returning * into r;
  update public.beo_documents set current_revision_id = r.id where id = doc.id;
  if previous.id is not null then
    update public.event_tasks
       set needs_review = true,
           review_reason = 'BEO revision ' || r.revision_no || ' changed this department''s work',
           updated_at = now()
     where event_id = doc.event_id and department = any(affected)
       and status <> 'completed';
  end if;
  insert into public.notifications (venue_id, user_id, kind, title, body, event_id)
  select distinct r.venue_id, people.user_id, 'beo_revision',
         case when previous.id is null then 'BEO approved' else 'BEO revision approved' end,
         case when previous.id is null
              then 'The BEO for this event is approved. Review your department section.'
              else 'Revision ' || r.revision_no || ' changed your department''s work. Review the flagged tasks.' end,
         doc.event_id
    from (
      select s.user_id from public.event_staff s
       where s.event_id = doc.event_id and s.department = any(affected)
         and s.user_id is not null
      union
      select m.user_id from public.department_memberships m
       where m.venue_id = r.venue_id and m.department = any(affected)
    ) people;
  return r;
end;
$$;

-- Names shown in staffing use profile names. A missing name stays neutral and
-- never falls back to a private email address.
create or replace function public.create_user_profile()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.user_profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
      nullif(trim(new.raw_user_meta_data->>'name'), ''),
      'Team member'
    )
  ) on conflict (id) do nothing;
  return new;
end;
$$;
create trigger create_user_profile_after_signup
after insert on auth.users
for each row execute function public.create_user_profile();

insert into public.user_profiles (id, display_name)
select u.id,
       coalesce(
         nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
         nullif(trim(u.raw_user_meta_data->>'name'), ''),
         'Team member'
       )
  from auth.users u
on conflict (id) do nothing;

create or replace function public.list_venue_members(p_venue uuid)
returns table (user_id uuid, display_name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not (public.has_permission(p_venue, 'deploy_staff') or
          public.has_permission(p_venue, 'manage_configuration')) then
    raise exception 'Not authorized to list people' using errcode = '42501';
  end if;
  return query
  select m.user_id,
         case when nullif(trim(p.display_name), '') is null or
                   trim(p.display_name) = 'Team member'
              then 'Team member ' || left(m.user_id::text, 8)
              else trim(p.display_name) end
    from public.venue_memberships m
    left join public.user_profiles p on p.id = m.user_id
   where m.venue_id = p_venue and m.status = 'active'
   order by coalesce(nullif(trim(p.display_name), ''), 'Team member'), m.user_id;
end;
$$;

-- Manager and director closeout sign-offs must come from different people.
alter table public.event_closeouts
  add constraint closeout_distinct_signers_check check (
    manager_signed_by is null or director_signed_by is null or
    manager_signed_by <> director_signed_by
  );

create or replace function public.guard_closeout_lifecycle()
returns trigger language plpgsql security definer set search_path = public
as $$
declare event_status text;
begin
  select status into event_status from public.events where id = new.event_id;
  if event_status not in ('breakdown', 'closed') then
    raise exception 'The event must be in breakdown before closeout' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if old.status = 'signed' and new is distinct from old then
      raise exception 'A signed closeout cannot be changed' using errcode = '23514';
    end if;
    if old.manager_signed_at is not null and
       (new.manager_signed_by is distinct from old.manager_signed_by or
        new.manager_signed_at is distinct from old.manager_signed_at) then
      raise exception 'The manager sign-off cannot be repeated or replaced'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger closeout_lifecycle_guard before insert or update
  on public.event_closeouts for each row
  execute function public.guard_closeout_lifecycle();

-- Creating the event and its required task set is one transaction. A task
-- generation error cannot leave a duplicate draft behind on a form retry.
create or replace function public.create_event_with_tasks(p_draft jsonb)
returns public.events language plpgsql security definer set search_path = public
as $$
declare
  ev public.events%rowtype;
  target_venue uuid := (p_draft ->> 'venue_id')::uuid;
begin
  if not public.has_permission(target_venue, 'manage_events') then
    raise exception 'Not authorized to create events' using errcode = '42501';
  end if;
  insert into public.events (
    venue_id, name, event_type, service_start, service_end,
    guaranteed_guests, manager_name, notes, created_by
  ) values (
    target_venue, p_draft ->> 'name', p_draft ->> 'event_type',
    (p_draft ->> 'service_start')::timestamptz,
    (p_draft ->> 'service_end')::timestamptz,
    coalesce((p_draft ->> 'guaranteed_guests')::integer, 0),
    coalesce(p_draft ->> 'manager_name', ''),
    coalesce(p_draft ->> 'notes', ''), auth.uid()
  ) returning * into ev;
  perform public.generate_event_tasks(ev.id);
  return ev;
end;
$$;
revoke execute on function public.create_event_with_tasks(jsonb) from public, anon;
grant execute on function public.create_event_with_tasks(jsonb) to authenticated;

-- Serialize changes to director access and count only active directors.
create or replace function public.set_membership_status(
  p_venue uuid, p_user uuid, p_active boolean
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can change access' using errcode = '42501';
  end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'You cannot suspend your own access';
  end if;
  perform 1 from public.venues where id = p_venue for update;
  if not found then raise exception 'Venue not found' using errcode = 'P0002'; end if;
  if not p_active and exists (
    select 1 from public.role_assignments
    where venue_id = p_venue and user_id = p_user and role_code = 'director'
  ) and not exists (
    select 1 from public.role_assignments ra
    join public.venue_memberships m
      on m.venue_id = ra.venue_id and m.user_id = ra.user_id
    where ra.venue_id = p_venue and ra.role_code = 'director'
      and ra.user_id <> p_user and m.status = 'active'
  ) then
    raise exception 'The venue must keep at least one active director';
  end if;
  update public.venue_memberships
     set status = case when p_active then 'active' else 'suspended' end
   where venue_id = p_venue and user_id = p_user;
  if not found then raise exception 'Venue member not found' using errcode = 'P0002'; end if;
end;
$$;

create or replace function public.set_person_role(
  p_venue uuid, p_user uuid, p_role text, p_on boolean
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can change roles' using errcode = '42501';
  end if;
  if not exists (select 1 from public.roles where code = p_role) then
    raise exception 'Unknown role %', p_role;
  end if;
  perform 1 from public.venues where id = p_venue for update;
  if not found then raise exception 'Venue not found' using errcode = 'P0002'; end if;
  if not exists (
    select 1 from public.venue_memberships
    where venue_id = p_venue and user_id = p_user
  ) then
    raise exception 'That person is not a member of this venue';
  end if;
  if p_role = 'director' and not p_on and exists (
    select 1 from public.role_assignments
    where venue_id = p_venue and user_id = p_user and role_code = 'director'
  ) and not exists (
    select 1 from public.role_assignments ra
    join public.venue_memberships m
      on m.venue_id = ra.venue_id and m.user_id = ra.user_id
    where ra.venue_id = p_venue and ra.role_code = 'director'
      and ra.user_id <> p_user and m.status = 'active'
  ) then
    raise exception 'The venue must keep at least one active director';
  end if;
  if p_on then
    insert into public.role_assignments (venue_id, user_id, role_code)
    values (p_venue, p_user, p_role)
    on conflict (venue_id, user_id, role_code) do nothing;
  else
    delete from public.role_assignments
     where venue_id = p_venue and user_id = p_user and role_code = p_role;
  end if;
end;
$$;

-- Support the tenant-safe foreign keys and event detail screens.
create index if not exists event_briefings_event_idx
  on public.event_briefings(event_id);
create index if not exists event_menu_items_event_idx
  on public.event_menu_items(event_id);
create index if not exists culinary_batch_history_batch_idx
  on public.culinary_batch_history(batch_id);
create index if not exists event_announcements_event_idx
  on public.event_announcements(event_id);
create index if not exists task_comments_task_idx
  on public.task_comments(task_id);
create index if not exists operational_incidents_event_idx
  on public.operational_incidents(event_id);
create index if not exists event_spaces_space_idx
  on public.event_spaces(venue_space_id);
