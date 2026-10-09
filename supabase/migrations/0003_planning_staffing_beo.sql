-- CUTX Premium Command: Phase 2 remainder.
-- Event task generation, suites, staffing and briefings, and BEO revisions with acknowledgments.

-- ---------------------------------------------------------------------------
-- Task generation from templates
-- ---------------------------------------------------------------------------
create table task_templates (
  id uuid primary key default gen_random_uuid(),
  event_type text not null default '*',          -- '*' applies to every event type
  department text not null,
  title text not null,
  is_required boolean not null default true,
  hours_before_service numeric not null default 2 check (hours_before_service >= 0)
);

insert into task_templates (event_type, department, title, is_required, hours_before_service) values
  ('*', 'suites', 'Suite setup walkthrough', true, 4),
  ('*', 'suites', 'Suite catering delivery confirmed', true, 1),
  ('*', 'banquets', 'Room setup complete', true, 3),
  ('*', 'banquets', 'Captain sign-off', true, 0.5),
  ('*', 'culinary', 'Production ready', true, 2),
  ('*', 'beverage', 'Bar opening inspection', true, 1.5),
  ('*', 'lounge', 'Lounge readiness check', true, 2),
  ('*', 'operations', 'Staff briefing acknowledged', true, 1);

alter table event_tasks
  add column template_id uuid references task_templates(id) on delete set null,
  add column needs_review boolean not null default false,
  add column review_reason text not null default '';

create index event_tasks_template_idx on event_tasks(event_id, template_id);

alter table task_templates enable row level security;
create policy task_templates_read on task_templates for select to authenticated using (true);

-- Idempotent: safe to call again after a template change. Only adds tasks that do not exist yet.
create or replace function public.generate_event_tasks(p_event uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  inserted integer;
begin
  select * into ev from events where id = p_event;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(ev.venue_id, 'manage_events') then
    raise exception 'Not authorized to generate tasks' using errcode = '42501';
  end if;

  insert into event_tasks (venue_id, event_id, department, title, is_required, due_at, template_id)
  select ev.venue_id, ev.id, t.department, t.title, t.is_required,
         ev.service_start - make_interval(mins => round(t.hours_before_service * 60)::int),
         t.id
  from task_templates t
  where (t.event_type = '*' or t.event_type = ev.event_type)
    and not exists (
      select 1 from event_tasks x where x.event_id = ev.id and x.template_id = t.id
    );
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Suites
-- ---------------------------------------------------------------------------
create table venue_suites (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  name text not null,
  location text not null default '',
  capacity integer check (capacity is null or capacity >= 0),
  service_zone text not null default '',
  created_at timestamptz not null default now(),
  unique (venue_id, name)
);

create table suite_event_assignments (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  suite_id uuid not null references venue_suites(id) on delete cascade,
  state text not null default 'not_started' check (state in
    ('not_started','setup_in_progress','ready','in_service','closing','closed')),
  attendant_name text not null default '',
  runner_name text not null default '',
  guest_contact text not null default '',
  dietary_notes text not null default '',
  special_instructions text not null default '',
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  unique (event_id, suite_id)
);

create table suite_state_history (
  id bigint generated always as identity primary key,
  assignment_id uuid not null references suite_event_assignments(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  from_state text,
  to_state text not null,
  actor_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- Forward-only, one step at a time. Suite staff and managers both hold update_tasks.
create or replace function public.set_suite_state(p_assignment uuid, p_to text, p_expected_version integer)
returns suite_event_assignments
language plpgsql security definer set search_path = public
as $$
declare
  a suite_event_assignments%rowtype;
  order_list text[] := array['not_started','setup_in_progress','ready','in_service','closing','closed'];
  fi integer;
  ti integer;
  previous text;
begin
  select * into a from suite_event_assignments where id = p_assignment for update;
  if not found then
    raise exception 'Suite assignment not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(a.venue_id, 'update_tasks') then
    raise exception 'Not authorized to change suite state' using errcode = '42501';
  end if;
  if a.version <> p_expected_version then
    raise exception 'Conflict: this suite was changed by someone else. Refresh and try again.' using errcode = '40001';
  end if;

  fi := array_position(order_list, a.state);
  ti := array_position(order_list, p_to);
  if ti is null or ti <> fi + 1 then
    raise exception 'Suite moves one step at a time (% to % is not allowed)', a.state, p_to;
  end if;

  previous := a.state;
  update suite_event_assignments
     set state = p_to, version = version + 1, updated_at = now()
   where id = a.id
  returning * into a;

  insert into suite_state_history (assignment_id, venue_id, from_state, to_state)
  values (a.id, a.venue_id, previous, p_to);

  return a;
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff deployment and briefings
-- ---------------------------------------------------------------------------
create table event_staff (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  display_name text not null default '',       -- empty display_name with no user = uncovered position
  role_label text not null default '',
  department text not null default 'operations',
  suite_assignment_id uuid references suite_event_assignments(id) on delete set null,
  zone text not null default '',
  station text not null default '',
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);
create index event_staff_event_idx on event_staff(event_id);

create table event_briefings (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  title text not null,
  body text not null default '',
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table briefing_acknowledgments (
  briefing_id uuid not null references event_briefings(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key (briefing_id, user_id)
);

-- ---------------------------------------------------------------------------
-- BEO: immutable revisions, approval, department acknowledgment
-- ---------------------------------------------------------------------------
create table beo_documents (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null unique references events(id) on delete cascade,
  title text not null,
  current_revision_id uuid,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table beo_revisions (
  id uuid primary key default gen_random_uuid(),
  beo_id uuid not null references beo_documents(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  revision_no integer not null check (revision_no >= 1),
  status text not null default 'draft' check (status in ('draft','approved','superseded')),
  content jsonb not null,                 -- { "departments": [...], "guests": n, "timeline": [...], ... }
  summary text not null default '',
  author_id uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique (beo_id, revision_no)
);

create table beo_acknowledgments (
  revision_id uuid not null references beo_revisions(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  department text not null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key (revision_id, department, user_id)
);

create or replace function public.create_beo(p_event uuid, p_title text, p_content jsonb, p_summary text)
returns beo_documents
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  doc beo_documents%rowtype;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  if not public.has_permission(ev.venue_id, 'manage_events') then
    raise exception 'Not authorized to create BEOs' using errcode = '42501';
  end if;
  if ev.status in ('closed', 'cancelled') then
    raise exception 'This event is closed to changes';
  end if;

  insert into beo_documents (venue_id, event_id, title)
  values (ev.venue_id, ev.id, p_title)
  returning * into doc;

  insert into beo_revisions (beo_id, venue_id, revision_no, status, content, summary)
  values (doc.id, doc.venue_id, 1, 'draft', p_content, coalesce(p_summary, 'Initial BEO'));

  return doc;
end;
$$;

-- Never edits an existing revision. Creates the next one as a draft for approval.
create or replace function public.propose_beo_revision(
  p_beo uuid,
  p_content jsonb,
  p_summary text,
  p_expected_revision integer
)
returns beo_revisions
language plpgsql security definer set search_path = public
as $$
declare
  doc beo_documents%rowtype;
  latest integer;
  r beo_revisions%rowtype;
begin
  select * into doc from beo_documents where id = p_beo;
  if not found then raise exception 'BEO not found' using errcode = 'P0002'; end if;
  if not public.has_permission(doc.venue_id, 'manage_events') then
    raise exception 'Not authorized to revise BEOs' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_summary, ''))) = 0 then
    raise exception 'Describe what changed in this revision';
  end if;

  select max(revision_no) into latest from beo_revisions where beo_id = doc.id;
  if latest <> p_expected_revision then
    raise exception 'Conflict: a newer BEO revision (%) exists. Refresh and try again.', latest using errcode = '40001';
  end if;

  insert into beo_revisions (beo_id, venue_id, revision_no, status, content, summary)
  values (doc.id, doc.venue_id, latest + 1, 'draft', p_content, p_summary)
  returning * into r;

  return r;
end;
$$;

-- Approving supersedes the previous approved revision and flags affected departments' open tasks.
create or replace function public.approve_beo_revision(p_revision uuid)
returns beo_revisions
language plpgsql security definer set search_path = public
as $$
declare
  r beo_revisions%rowtype;
  doc beo_documents%rowtype;
  previous_approved uuid;
  affected text[];
  flagged integer;
begin
  select * into r from beo_revisions where id = p_revision for update;
  if not found then raise exception 'Revision not found' using errcode = 'P0002'; end if;
  if not public.has_permission(r.venue_id, 'approve_beo') then
    raise exception 'Only directors can approve BEOs' using errcode = '42501';
  end if;
  if r.status <> 'draft' then
    raise exception 'Only draft revisions can be approved (this one is %)', r.status;
  end if;

  select * into doc from beo_documents where id = r.beo_id;
  if doc.current_revision_id is not null then
    previous_approved := doc.current_revision_id;
  end if;

  update beo_revisions set status = 'superseded' where beo_id = doc.id and status = 'approved';

  update beo_revisions
     set status = 'approved', approved_by = auth.uid(), approved_at = now()
   where id = r.id
  returning * into r;

  update beo_documents set current_revision_id = r.id where id = doc.id;

  -- Only revisions after the first approval affect work already planned.
  if previous_approved is not null then
    select coalesce(array_agg(value::text), '{}') into affected
    from jsonb_array_elements_text(coalesce(r.content -> 'departments', '[]'::jsonb));

    update event_tasks
       set needs_review = true,
           review_reason = 'BEO revision ' || r.revision_no || ' changed this department''s work',
           updated_at = now()
     where event_id = doc.event_id
       and department = any(affected)
       and status <> 'completed';
    get diagnostics flagged = row_count;
  end if;

  return r;
end;
$$;

create or replace function public.acknowledge_beo_revision(p_revision uuid, p_department text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  r beo_revisions%rowtype;
begin
  select * into r from beo_revisions where id = p_revision;
  if not found then raise exception 'Revision not found' using errcode = 'P0002'; end if;
  if not public.is_venue_member(r.venue_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if not public.has_permission(r.venue_id, 'update_tasks') then
    raise exception 'Not authorized to acknowledge BEOs' using errcode = '42501';
  end if;
  if r.status <> 'approved' then
    raise exception 'Only approved revisions can be acknowledged';
  end if;

  insert into beo_acknowledgments (revision_id, venue_id, department, user_id)
  values (r.id, r.venue_id, p_department, auth.uid())
  on conflict do nothing;

  -- Acknowledging clears review flags for that department on this event.
  update event_tasks t
     set needs_review = false, review_reason = '', updated_at = now()
   where t.event_id = (select event_id from beo_documents where id = r.beo_id)
     and t.department = p_department
     and t.needs_review;

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants and RLS
-- ---------------------------------------------------------------------------
revoke execute on function public.generate_event_tasks(uuid) from public, anon;
revoke execute on function public.set_suite_state(uuid, text, integer) from public, anon;
revoke execute on function public.create_beo(uuid, text, jsonb, text) from public, anon;
revoke execute on function public.propose_beo_revision(uuid, jsonb, text, integer) from public, anon;
revoke execute on function public.approve_beo_revision(uuid) from public, anon;
revoke execute on function public.acknowledge_beo_revision(uuid, text) from public, anon;
grant execute on function public.generate_event_tasks(uuid) to authenticated;
grant execute on function public.set_suite_state(uuid, text, integer) to authenticated;
grant execute on function public.create_beo(uuid, text, jsonb, text) to authenticated;
grant execute on function public.propose_beo_revision(uuid, jsonb, text, integer) to authenticated;
grant execute on function public.approve_beo_revision(uuid) to authenticated;
grant execute on function public.acknowledge_beo_revision(uuid, text) to authenticated;

alter table venue_suites enable row level security;
alter table suite_event_assignments enable row level security;
alter table suite_state_history enable row level security;
alter table event_staff enable row level security;
alter table event_briefings enable row level security;
alter table briefing_acknowledgments enable row level security;
alter table beo_documents enable row level security;
alter table beo_revisions enable row level security;
alter table beo_acknowledgments enable row level security;

-- Suites: members read; managers configure.
create policy venue_suites_read on venue_suites for select to authenticated using (public.is_venue_member(venue_id));
create policy venue_suites_write on venue_suites for all to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));

-- Suite assignments: members read; managers create and edit details. State changes go through set_suite_state.
-- A table-level UPDATE grant overrides a column revoke, so revoke the table and grant the editable columns only.
revoke update on suite_event_assignments from authenticated, anon;
grant update (attendant_name, runner_name, guest_contact, dietary_notes, special_instructions, updated_at)
  on suite_event_assignments to authenticated;
create policy suite_assignments_read on suite_event_assignments for select to authenticated using (public.is_venue_member(venue_id));
create policy suite_assignments_insert on suite_event_assignments for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events'));
create policy suite_assignments_update on suite_event_assignments for update to authenticated
  using (public.has_permission(venue_id, 'deploy_staff'))
  with check (public.has_permission(venue_id, 'deploy_staff'));
create policy suite_assignments_delete on suite_event_assignments for delete to authenticated
  using (public.has_permission(venue_id, 'manage_events'));

create policy suite_history_read on suite_state_history for select to authenticated using (public.is_venue_member(venue_id));

-- Staff: managers see and edit the roster; a person sees their own assignments.
create policy event_staff_read on event_staff for select to authenticated
  using (public.has_permission(venue_id, 'deploy_staff') or user_id = auth.uid());
create policy event_staff_write on event_staff for all to authenticated
  using (public.has_permission(venue_id, 'deploy_staff'))
  with check (public.has_permission(venue_id, 'deploy_staff'));

-- Briefings: members read; deploy_staff publishes; each person acknowledges their own.
create policy briefings_read on event_briefings for select to authenticated using (public.is_venue_member(venue_id));
create policy briefings_write on event_briefings for insert to authenticated
  with check (public.has_permission(venue_id, 'deploy_staff'));
create policy briefing_ack_read on briefing_acknowledgments for select to authenticated using (public.is_venue_member(venue_id));
create policy briefing_ack_insert on briefing_acknowledgments for insert to authenticated
  with check (user_id = auth.uid() and public.is_venue_member(venue_id));

-- Task review flags are set and cleared only by the BEO functions. Clients may change status and completion.
revoke update on event_tasks from authenticated, anon;
grant update (status, completed_at, completed_by, updated_at) on event_tasks to authenticated;

-- BEO: members read. All writes go through the functions above, which keep revisions immutable.
revoke insert, update, delete on beo_documents, beo_revisions, beo_acknowledgments from authenticated, anon;
create policy beo_documents_read on beo_documents for select to authenticated using (public.is_venue_member(venue_id));
create policy beo_revisions_read on beo_revisions for select to authenticated using (public.is_venue_member(venue_id));
create policy beo_ack_read on beo_acknowledgments for select to authenticated using (public.is_venue_member(venue_id));
