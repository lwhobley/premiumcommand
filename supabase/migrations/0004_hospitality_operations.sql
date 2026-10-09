-- CUTX Premium Command: Phase 3 hospitality operations.
-- Banquet timeline, culinary production and handoffs, inspections, communications, and closeout.

-- ---------------------------------------------------------------------------
-- Banquet timeline
-- ---------------------------------------------------------------------------
create table banquet_timeline_items (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  department text not null default 'banquets',
  assignee_name text not null default '',
  scheduled_start timestamptz not null,
  target_completion timestamptz,
  actual_completion timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','done','late','blocked')),
  notes text not null default '',
  depends_on uuid references banquet_timeline_items(id) on delete set null,
  escalate_to text not null default '',
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index banquet_timeline_event_idx on banquet_timeline_items(event_id, scheduled_start);

-- Start, finish, or block a timeline item. Finishing a dependent item needs its dependency done first.
create or replace function public.update_timeline_item(p_item uuid, p_status text, p_expected_version integer, p_note text default '')
returns banquet_timeline_items
language plpgsql security definer set search_path = public
as $$
declare
  t banquet_timeline_items%rowtype;
  dep_status text;
begin
  select * into t from banquet_timeline_items where id = p_item for update;
  if not found then raise exception 'Timeline item not found' using errcode = 'P0002'; end if;
  if not public.has_permission(t.venue_id, 'manage_banquets') and not public.has_permission(t.venue_id, 'update_tasks') then
    raise exception 'Not authorized to update the timeline' using errcode = '42501';
  end if;
  if t.version <> p_expected_version then
    raise exception 'Conflict: this timeline item changed. Refresh and try again.' using errcode = '40001';
  end if;
  if p_status not in ('scheduled','in_progress','done','late','blocked') then
    raise exception 'Unknown status %', p_status;
  end if;
  if p_status = 'done' and t.depends_on is not null then
    select status into dep_status from banquet_timeline_items where id = t.depends_on;
    if dep_status is distinct from 'done' then
      raise exception 'This depends on an item that is not done yet';
    end if;
  end if;
  if p_status = 'blocked' and length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'A reason is required to block a timeline item';
  end if;

  update banquet_timeline_items set
    status = p_status,
    actual_completion = case when p_status = 'done' then now() else null end,
    notes = case when length(trim(coalesce(p_note, ''))) > 0 then p_note else notes end,
    version = version + 1,
    updated_at = now()
  where id = t.id
  returning * into t;
  return t;
end;
$$;

-- ---------------------------------------------------------------------------
-- Culinary: menu items, batches, and the food handoff chain
-- ---------------------------------------------------------------------------
create table event_menu_items (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  name text not null,
  course text not null default '',
  dietary_tags text[] not null default '{}',
  allergens text not null default '',
  created_at timestamptz not null default now()
);

-- A batch is a set of one dish produced for a pickup point. Readiness is not delivery:
-- ready -> collected -> delivered -> received are separate, recorded steps.
create table culinary_batches (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  menu_item_id uuid references event_menu_items(id) on delete set null,
  description text not null,
  quantity integer not null default 1 check (quantity > 0),
  destination text not null default '',
  due_at timestamptz,
  state text not null default 'planned' check (state in
    ('planned','in_production','ready','collected','delivered','received')),
  ready_at timestamptz,
  collected_at timestamptz,
  delivered_at timestamptz,
  received_at timestamptz,
  received_by text not null default '',
  version integer not null default 1,
  created_at timestamptz not null default now()
);
create index culinary_batches_event_idx on culinary_batches(event_id, state);

create table culinary_batch_history (
  id bigint generated always as identity primary key,
  batch_id uuid not null references culinary_batches(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  from_state text,
  to_state text not null,
  actor_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create or replace function public.advance_culinary_batch(
  p_batch uuid,
  p_to text,
  p_expected_version integer,
  p_receiver text default ''
)
returns culinary_batches
language plpgsql security definer set search_path = public
as $$
declare
  b culinary_batches%rowtype;
  previous text;
  order_list text[] := array['planned','in_production','ready','collected','delivered','received'];
  fi integer;
  ti integer;
  allowed boolean;
begin
  select * into b from culinary_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found' using errcode = 'P0002'; end if;
  if b.version <> p_expected_version then
    raise exception 'Conflict: this batch changed. Refresh and try again.' using errcode = '40001';
  end if;

  fi := array_position(order_list, b.state);
  ti := array_position(order_list, p_to);
  if ti is null or ti <> fi + 1 then
    raise exception 'Batch moves one step at a time (% to % is not allowed)', b.state, p_to;
  end if;

  -- Who may take each step.
  allowed := case p_to
    when 'in_production' then public.has_permission(b.venue_id, 'view_culinary')
    when 'ready' then public.has_permission(b.venue_id, 'view_culinary')
    when 'collected' then public.has_permission(b.venue_id, 'manage_requests')
    when 'delivered' then public.has_permission(b.venue_id, 'manage_requests')
    when 'received' then public.has_permission(b.venue_id, 'update_tasks')
    else false
  end;
  if not allowed then
    raise exception 'Not authorized for this handoff step' using errcode = '42501';
  end if;
  if p_to = 'received' and length(trim(coalesce(p_receiver, ''))) = 0 then
    raise exception 'Record who received the delivery';
  end if;

  previous := b.state;
  update culinary_batches set
    state = p_to,
    ready_at = case when p_to = 'ready' then now() else ready_at end,
    collected_at = case when p_to = 'collected' then now() else collected_at end,
    delivered_at = case when p_to = 'delivered' then now() else delivered_at end,
    received_at = case when p_to = 'received' then now() else received_at end,
    received_by = case when p_to = 'received' then p_receiver else received_by end,
    version = version + 1
  where id = b.id
  returning * into b;

  insert into culinary_batch_history (batch_id, venue_id, from_state, to_state)
  values (b.id, b.venue_id, previous, p_to);
  return b;
end;
$$;

-- ---------------------------------------------------------------------------
-- Inspections and checklists
-- ---------------------------------------------------------------------------
create table checklist_templates (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references venues(id) on delete cascade,   -- null = shared default
  category text not null check (category in (
    'suite_opening','suite_closing','lounge_readiness','bar_opening','bar_closing',
    'banquet_setup','banquet_breakdown','culinary_readiness','guest_area_cleanliness',
    'equipment_readiness','event_closeout')),
  name text not null,
  created_at timestamptz not null default now()
);

create table checklist_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references checklist_templates(id) on delete cascade,
  position integer not null default 0,
  label text not null,
  response_type text not null check (response_type in ('yes_no','pass_fail','numeric','text','photo')),
  requires_manager_approval boolean not null default false,
  department text not null default 'operations'
);

create table inspection_instances (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  template_id uuid not null references checklist_templates(id),
  subject text not null default '',
  status text not null default 'open' check (status in ('open','completed','approved')),
  completed_by uuid references auth.users(id),
  completed_at timestamptz,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table inspection_responses (
  id uuid primary key default gen_random_uuid(),
  instance_id uuid not null references inspection_instances(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  item_id uuid not null references checklist_items(id) on delete cascade,
  passed boolean not null,
  numeric_value numeric,
  text_value text not null default '',
  photo_url text not null default '',
  created_at timestamptz not null default now(),
  unique (instance_id, item_id)
);

-- Completing an inspection records every response. A failed item opens a corrective action task.
create or replace function public.complete_inspection(p_instance uuid, p_responses jsonb)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  inst inspection_instances%rowtype;
  item record;
  resp jsonb;
  failures integer := 0;
begin
  select * into inst from inspection_instances where id = p_instance for update;
  if not found then raise exception 'Inspection not found' using errcode = 'P0002'; end if;
  if not public.has_permission(inst.venue_id, 'run_inspections') then
    raise exception 'Not authorized to complete inspections' using errcode = '42501';
  end if;
  if inst.status <> 'open' then
    raise exception 'This inspection is already %', inst.status;
  end if;

  -- Every checklist item needs a response, so nothing is skipped silently.
  for item in select * from checklist_items where template_id = inst.template_id loop
    resp := (select v.value from jsonb_array_elements(p_responses) v where v.value->>'item_id' = item.id::text limit 1);
    if resp is null then
      raise exception 'Missing response for "%"', item.label;
    end if;

    insert into inspection_responses (instance_id, venue_id, item_id, passed, numeric_value, text_value, photo_url)
    values (
      inst.id, inst.venue_id, item.id,
      coalesce((resp->>'passed')::boolean, false),
      nullif(resp->>'numeric_value', '')::numeric,
      coalesce(resp->>'text_value', ''),
      coalesce(resp->>'photo_url', '')
    );

    if not coalesce((resp->>'passed')::boolean, false) then
      failures := failures + 1;
      insert into event_tasks (venue_id, event_id, department, title, is_required, status)
      values (inst.venue_id, inst.event_id, item.department,
              'Corrective: ' || item.label || ' (' || inst.subject || ')', true, 'not_started');
    end if;
  end loop;

  update inspection_instances
     set status = 'completed', completed_by = auth.uid(), completed_at = now()
   where id = inst.id;

  return failures;
end;
$$;

create or replace function public.approve_inspection(p_instance uuid)
returns inspection_instances
language plpgsql security definer set search_path = public
as $$
declare
  inst inspection_instances%rowtype;
begin
  select * into inst from inspection_instances where id = p_instance for update;
  if not found then raise exception 'Inspection not found' using errcode = 'P0002'; end if;
  if not public.has_permission(inst.venue_id, 'review_inspections') then
    raise exception 'Not authorized to approve inspections' using errcode = '42501';
  end if;
  if inst.status <> 'completed' then
    raise exception 'Only completed inspections can be approved';
  end if;
  update inspection_instances
     set status = 'approved', approved_by = auth.uid(), approved_at = now()
   where id = inst.id
  returning * into inst;
  return inst;
end;
$$;

-- Shared default checklists. Venues add their own templates with venue_id set.
with t as (insert into checklist_templates (category, name) values ('suite_opening', 'Suite opening') returning id)
insert into checklist_items (template_id, position, label, response_type, department)
select id, 1, 'Furniture and linens set', 'pass_fail', 'suites' from t
union all select id, 2, 'Guest amenities stocked', 'yes_no', 'suites' from t
union all select id, 3, 'Suite temperature checked', 'pass_fail', 'suites' from t;

with t as (insert into checklist_templates (category, name) values ('bar_opening', 'Bar opening') returning id)
insert into checklist_items (template_id, position, label, response_type, department)
select id, 1, 'Bar stocked and labeled', 'yes_no', 'beverage' from t
union all select id, 2, 'Ice bin filled', 'pass_fail', 'beverage' from t
union all select id, 3, 'Glassware ready', 'pass_fail', 'beverage' from t;

with t as (insert into checklist_templates (category, name) values ('culinary_readiness', 'Culinary readiness') returning id)
insert into checklist_items (template_id, position, label, response_type, requires_manager_approval, department)
select id, 1, 'Mise en place complete', 'pass_fail', false, 'culinary' from t
union all select id, 2, 'Allergen cards posted', 'yes_no', true, 'culinary' from t;

with t as (insert into checklist_templates (category, name) values ('event_closeout', 'Event closeout walkthrough') returning id)
insert into checklist_items (template_id, position, label, response_type, department)
select id, 1, 'Guest areas cleaned', 'pass_fail', 'operations' from t
union all select id, 2, 'Equipment returned', 'yes_no', 'operations' from t;

-- ---------------------------------------------------------------------------
-- Communications
-- ---------------------------------------------------------------------------
create table event_announcements (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  body text not null check (length(trim(body)) > 0),
  author_id uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table task_comments (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  task_id uuid not null references event_tasks(id) on delete cascade,
  body text not null check (length(trim(body)) > 0),
  author_id uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null default '',
  event_id uuid references events(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user_idx on notifications(user_id, read_at);

-- Every rostered person on the event gets the announcement as a notification.
create or replace function public.notify_announcement()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into notifications (venue_id, user_id, kind, title, body, event_id)
  select distinct new.venue_id, s.user_id, 'announcement', 'Event announcement', new.body, new.event_id
  from event_staff s
  where s.event_id = new.event_id and s.user_id is not null;
  return new;
end;
$$;

create trigger event_announcements_notify
after insert on event_announcements
for each row execute function public.notify_announcement();

-- ---------------------------------------------------------------------------
-- Operational incidents (guest concerns, culinary issues, inspection escalations)
-- ---------------------------------------------------------------------------
create table operational_incidents (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  kind text not null check (kind in ('guest_concern','culinary_issue','equipment','safety','other')),
  description text not null check (length(trim(description)) > 0),
  reported_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.report_incident(p_event uuid, p_kind text, p_description text)
returns operational_incidents
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  r operational_incidents%rowtype;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  if not public.is_venue_member(ev.venue_id) then raise exception 'Not authorized' using errcode = '42501'; end if;
  insert into operational_incidents (venue_id, event_id, kind, description)
  values (ev.venue_id, ev.id, p_kind, p_description)
  returning * into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Closeout and recap
-- ---------------------------------------------------------------------------
create table event_closeouts (
  event_id uuid primary key references events(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  status text not null default 'open' check (status in ('open','submitted','signed')),
  recap jsonb not null default '{}'::jsonb,
  department_notes text not null default '',
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  manager_signed_by uuid references auth.users(id),
  manager_signed_at timestamptz,
  director_signed_by uuid references auth.users(id),
  director_signed_at timestamptz
);

-- Builds the operational recap. Financial and payment data is never included.
create or replace function public.build_event_recap(p_event uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  ev events%rowtype;
  tasks_total integer; tasks_done integer; tasks_overdue integer;
  req_total integer; req_completed integer;
  avg_response_minutes numeric;
  inspections_failed integer; corrective integer;
  incidents integer; late_deliveries integer;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  if not public.is_venue_member(ev.venue_id) then raise exception 'Not authorized' using errcode = '42501'; end if;

  select count(*) filter (where is_required),
         count(*) filter (where is_required and status = 'completed'),
         count(*) filter (where is_required and status <> 'completed' and due_at < now())
    into tasks_total, tasks_done, tasks_overdue
    from event_tasks where event_id = p_event;

  select count(*), count(*) filter (where status = 'completed'),
         avg(extract(epoch from (acknowledged_at - created_at)) / 60) filter (where acknowledged_at is not null)
    into req_total, req_completed, avg_response_minutes
    from service_requests where event_id = p_event;

  select count(*) into inspections_failed
    from inspection_responses r join inspection_instances i on i.id = r.instance_id
   where i.event_id = p_event and not r.passed;

  select count(*) into corrective from event_tasks where event_id = p_event and title like 'Corrective:%';
  select count(*) into incidents from operational_incidents where event_id = p_event;

  select count(*) into late_deliveries
    from culinary_batches where event_id = p_event and delivered_at is not null and due_at is not null and delivered_at > due_at;

  return jsonb_build_object(
    'event', jsonb_build_object('name', ev.name, 'type', ev.event_type, 'service_start', ev.service_start,
                                'service_end', ev.service_end, 'guaranteed_guests', ev.guaranteed_guests,
                                'manager', ev.manager_name, 'status', ev.status),
    'tasks', jsonb_build_object('required', tasks_total, 'completed', tasks_done, 'overdue', tasks_overdue),
    'requests', jsonb_build_object('total', req_total, 'completed', req_completed,
                                   'avg_response_minutes', round(coalesce(avg_response_minutes, 0), 1)),
    'inspections', jsonb_build_object('failed_items', inspections_failed, 'corrective_actions', corrective),
    'incidents', incidents,
    'late_deliveries', late_deliveries,
    'generated_at', now()
  );
end;
$$;

-- Creates or refreshes the closeout record and its recap.
create or replace function public.start_event_closeout(p_event uuid)
returns event_closeouts
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  c event_closeouts%rowtype;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  if not public.has_permission(ev.venue_id, 'close_out_events') then
    raise exception 'Not authorized to start closeout' using errcode = '42501';
  end if;
  insert into event_closeouts (event_id, venue_id, recap)
  values (ev.id, ev.venue_id, public.build_event_recap(ev.id))
  on conflict (event_id) do update set recap = excluded.recap
  where event_closeouts.status = 'open'
  returning * into c;
  if c.event_id is null then
    select * into c from event_closeouts where event_id = ev.id;
  end if;
  return c;
end;
$$;

-- Submitting freezes the recap for review. Sign-off by the manager, then the director, is required before closing.
create or replace function public.sign_event_closeout(p_event uuid, p_role text)
returns event_closeouts
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  c event_closeouts%rowtype;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  select * into c from event_closeouts where event_id = p_event for update;
  if not found then raise exception 'Start the closeout first'; end if;

  if p_role = 'submit' then
    if not public.has_permission(ev.venue_id, 'close_out_events') then
      raise exception 'Not authorized to submit closeout' using errcode = '42501';
    end if;
    if c.status <> 'open' then raise exception 'Closeout is already %', c.status; end if;
    update event_closeouts set status = 'submitted', recap = public.build_event_recap(p_event),
           submitted_by = auth.uid(), submitted_at = now()
     where event_id = p_event returning * into c;
  elsif p_role = 'manager' then
    if not public.has_permission(ev.venue_id, 'manage_events') then
      raise exception 'Only event managers can sign closeout' using errcode = '42501';
    end if;
    if c.status <> 'submitted' then raise exception 'Submit the closeout before signing'; end if;
    update event_closeouts set manager_signed_by = auth.uid(), manager_signed_at = now()
     where event_id = p_event returning * into c;
  elsif p_role = 'director' then
    if not public.has_permission(ev.venue_id, 'approve_beo') then
      raise exception 'Only directors can sign closeout' using errcode = '42501';
    end if;
    if c.manager_signed_at is null then raise exception 'The event manager must sign first'; end if;
    update event_closeouts set status = 'signed', director_signed_by = auth.uid(), director_signed_at = now()
     where event_id = p_event returning * into c;
  else
    raise exception 'Unknown closeout step %', p_role;
  end if;
  return c;
end;
$$;

-- Closing the event now requires a signed closeout. This replaces the Phase 1 function.
create or replace function public.transition_event(p_event_id uuid, p_to text)
returns events
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  lifecycle text[] := array['draft','planning','approved','setup','ready','in_service','breakdown','closed'];
  fi int;
  ti int;
  open_required int;
  closeout_status text;
begin
  select * into ev from events where id = p_event_id for update;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if not public.is_venue_member(ev.venue_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_to = 'cancelled' then
    if ev.status = 'closed' then
      raise exception 'Closed events cannot be cancelled';
    end if;
    if not public.has_permission(ev.venue_id, 'cancel_or_reopen_events') then
      raise exception 'Not authorized to cancel events' using errcode = '42501';
    end if;
  elsif ev.status = 'cancelled' then
    if p_to <> 'planning' then
      raise exception 'A cancelled event can only be reopened to planning';
    end if;
    if not public.has_permission(ev.venue_id, 'cancel_or_reopen_events') then
      raise exception 'Not authorized to reopen events' using errcode = '42501';
    end if;
  elsif ev.status = 'closed' and p_to = 'breakdown' then
    if not public.has_permission(ev.venue_id, 'cancel_or_reopen_events') then
      raise exception 'Not authorized to reopen events' using errcode = '42501';
    end if;
  else
    fi := array_position(lifecycle, ev.status);
    ti := array_position(lifecycle, p_to);
    if fi is null or ti is null or ti <> fi + 1 then
      raise exception 'Invalid transition from % to %', ev.status, p_to;
    end if;
    if not public.has_permission(ev.venue_id, 'manage_events') then
      raise exception 'Not authorized to manage events' using errcode = '42501';
    end if;
    if p_to = 'approved' and not public.has_permission(ev.venue_id, 'approve_beo') then
      raise exception 'Approval requires BEO approval permission' using errcode = '42501';
    end if;
    if p_to = 'ready' then
      select count(*) into open_required
      from event_tasks
      where event_id = ev.id and is_required and status <> 'completed';
      if open_required > 0 or not exists (select 1 from event_tasks where event_id = ev.id and is_required) then
        raise exception 'Required tasks are not all complete';
      end if;
    end if;
    if p_to = 'closed' then
      select status into closeout_status from event_closeouts where event_id = ev.id;
      if closeout_status is distinct from 'signed' then
        raise exception 'The closeout must be signed by the manager and director before the event closes';
      end if;
    end if;
  end if;

  update events
     set status = p_to, updated_at = now(), version = version + 1
   where id = ev.id
  returning * into ev;

  return ev;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants and RLS
-- ---------------------------------------------------------------------------
revoke execute on function public.update_timeline_item(uuid, text, integer, text) from public, anon;
revoke execute on function public.advance_culinary_batch(uuid, text, integer, text) from public, anon;
revoke execute on function public.complete_inspection(uuid, jsonb) from public, anon;
revoke execute on function public.approve_inspection(uuid) from public, anon;
revoke execute on function public.report_incident(uuid, text, text) from public, anon;
revoke execute on function public.build_event_recap(uuid) from public, anon;
revoke execute on function public.start_event_closeout(uuid) from public, anon;
revoke execute on function public.sign_event_closeout(uuid, text) from public, anon;
grant execute on function public.update_timeline_item(uuid, text, integer, text) to authenticated;
grant execute on function public.advance_culinary_batch(uuid, text, integer, text) to authenticated;
grant execute on function public.complete_inspection(uuid, jsonb) to authenticated;
grant execute on function public.approve_inspection(uuid) to authenticated;
grant execute on function public.report_incident(uuid, text, text) to authenticated;
grant execute on function public.build_event_recap(uuid) to authenticated;
grant execute on function public.start_event_closeout(uuid) to authenticated;
grant execute on function public.sign_event_closeout(uuid, text) to authenticated;

alter table banquet_timeline_items enable row level security;
alter table event_menu_items enable row level security;
alter table culinary_batches enable row level security;
alter table culinary_batch_history enable row level security;
alter table checklist_templates enable row level security;
alter table checklist_items enable row level security;
alter table inspection_instances enable row level security;
alter table inspection_responses enable row level security;
alter table event_announcements enable row level security;
alter table task_comments enable row level security;
alter table notifications enable row level security;
alter table operational_incidents enable row level security;
alter table event_closeouts enable row level security;

-- Timeline: members read; banquet managers add items; status changes go through the function.
revoke update on banquet_timeline_items from authenticated, anon;
grant update (title, department, assignee_name, scheduled_start, target_completion, notes, updated_at)
  on banquet_timeline_items to authenticated;
create policy timeline_read on banquet_timeline_items for select to authenticated using (public.is_venue_member(venue_id));
create policy timeline_insert on banquet_timeline_items for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_banquets'));
create policy timeline_update on banquet_timeline_items for update to authenticated
  using (public.has_permission(venue_id, 'manage_banquets'))
  with check (public.has_permission(venue_id, 'manage_banquets'));

-- Menu: culinary leads and managers maintain it; members read it.
create policy menu_read on event_menu_items for select to authenticated using (public.is_venue_member(venue_id));
create policy menu_write on event_menu_items for all to authenticated
  using (public.has_permission(venue_id, 'view_culinary'))
  with check (public.has_permission(venue_id, 'view_culinary'));

-- Batches: read by members; create by culinary; state changes only through the function.
revoke update, delete on culinary_batches from authenticated, anon;
grant update (description, quantity, destination, due_at) on culinary_batches to authenticated;
create policy batches_read on culinary_batches for select to authenticated using (public.is_venue_member(venue_id));
create policy batches_insert on culinary_batches for insert to authenticated
  with check (public.has_permission(venue_id, 'view_culinary'));
create policy batches_update on culinary_batches for update to authenticated
  using (public.has_permission(venue_id, 'view_culinary'))
  with check (public.has_permission(venue_id, 'view_culinary'));
create policy batch_history_read on culinary_batch_history for select to authenticated using (public.is_venue_member(venue_id));

-- Checklists: shared defaults (venue_id null) and venue-specific templates are readable by members.
create policy templates_read on checklist_templates for select to authenticated
  using (venue_id is null or public.is_venue_member(venue_id));
create policy templates_write on checklist_templates for all to authenticated
  using (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'))
  with check (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'));
create policy checklist_items_read on checklist_items for select to authenticated
  using (exists (select 1 from checklist_templates t where t.id = template_id and (t.venue_id is null or public.is_venue_member(t.venue_id))));

create policy inspections_read on inspection_instances for select to authenticated using (public.is_venue_member(venue_id));
create policy inspections_insert on inspection_instances for insert to authenticated
  with check (public.has_permission(venue_id, 'run_inspections'));
revoke update on inspection_instances from authenticated, anon;
create policy inspection_responses_read on inspection_responses for select to authenticated using (public.is_venue_member(venue_id));

-- Announcements and comments: members read; announcers and commenters write their own.
create policy announcements_read on event_announcements for select to authenticated using (public.is_venue_member(venue_id));
create policy announcements_insert on event_announcements for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events') and author_id = auth.uid());
create policy task_comments_read on task_comments for select to authenticated using (public.is_venue_member(venue_id));
create policy task_comments_insert on task_comments for insert to authenticated
  with check (public.is_venue_member(venue_id) and author_id = auth.uid());

-- Notifications: each person sees and marks only their own.
create policy notifications_read on notifications for select to authenticated using (user_id = auth.uid());
revoke update on notifications from authenticated, anon;
grant update (read_at) on notifications to authenticated;
create policy notifications_mark_read on notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Incidents: members read; reporting goes through report_incident.
revoke insert, update, delete on operational_incidents from authenticated, anon;
create policy incidents_read on operational_incidents for select to authenticated using (public.is_venue_member(venue_id));

-- Closeouts: members read; changes only through the functions.
revoke insert, update, delete on event_closeouts from authenticated, anon;
create policy closeouts_read on event_closeouts for select to authenticated using (public.is_venue_member(venue_id));

-- Notification trigger function is internal.
revoke execute on function public.notify_announcement() from public, anon, authenticated;
