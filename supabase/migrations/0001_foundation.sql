-- CUTX Premium Command: Phase 1 foundation.
-- Tenancy, roles, permissions, events, event tasks, audit log, RLS, and server-side lifecycle.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tenancy
-- ---------------------------------------------------------------------------
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table venues (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now()
);
create index venues_organization_id_idx on venues(organization_id);

create table user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now()
);

create table venue_memberships (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  unique (venue_id, user_id)
);
create index venue_memberships_user_id_idx on venue_memberships(user_id);

-- ---------------------------------------------------------------------------
-- Roles and permissions
-- ---------------------------------------------------------------------------
create table roles (
  code text primary key,
  name text not null
);

create table permissions (
  code text primary key,
  description text not null
);

create table role_permissions (
  role_code text not null references roles(code) on delete cascade,
  permission_code text not null references permissions(code) on delete cascade,
  primary key (role_code, permission_code)
);

create table role_assignments (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references roles(code),
  created_at timestamptz not null default now(),
  unique (venue_id, user_id, role_code)
);
create index role_assignments_user_id_idx on role_assignments(user_id);

insert into roles (code, name) values
  ('director', 'Director of Premium'),
  ('premium_manager', 'Premium Manager'),
  ('banquet_captain', 'Banquet Captain'),
  ('suite_attendant', 'Suite Attendant'),
  ('runner', 'Runner'),
  ('culinary_lead', 'Executive Chef / Culinary Lead'),
  ('beverage_lead', 'Bartender / Beverage Lead');

insert into permissions (code, description) values
  ('view_operations', 'View venue operational dashboards and events'),
  ('manage_events', 'Create and advance events'),
  ('approve_beo', 'Approve BEOs and significant revisions'),
  ('cancel_or_reopen_events', 'Cancel or reopen events'),
  ('deploy_staff', 'Manage event staff deployment'),
  ('update_tasks', 'Update event task status'),
  ('manage_requests', 'Create and fulfil service requests'),
  ('run_inspections', 'Complete inspections and checklists'),
  ('review_inspections', 'Review and sign off inspections'),
  ('view_culinary', 'View menus and production requirements'),
  ('manage_banquets', 'Manage banquet setup and service'),
  ('close_out_events', 'Complete event closeout'),
  ('view_reports', 'View recaps and analytics'),
  ('manage_configuration', 'Manage venue configuration');

insert into role_permissions (role_code, permission_code)
select 'director', code from permissions
union all select 'premium_manager', unnest(array['view_operations','manage_events','deploy_staff','update_tasks','manage_requests','run_inspections','review_inspections','view_culinary','view_reports'])
union all select 'banquet_captain', unnest(array['view_operations','update_tasks','manage_banquets','close_out_events','run_inspections','manage_requests','view_culinary'])
union all select 'suite_attendant', unnest(array['view_operations','update_tasks','run_inspections','manage_requests'])
union all select 'runner', unnest(array['view_operations','update_tasks','manage_requests'])
union all select 'culinary_lead', unnest(array['view_operations','view_culinary','update_tasks','manage_requests','run_inspections'])
union all select 'beverage_lead', unnest(array['view_operations','update_tasks','run_inspections','manage_requests']);

-- ---------------------------------------------------------------------------
-- Spaces and events
-- ---------------------------------------------------------------------------
create table venue_spaces (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  name text not null,
  space_type text not null,
  created_at timestamptz not null default now()
);

create table events (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  name text not null,
  event_type text not null,
  status text not null default 'draft' check (status in
    ('draft','planning','approved','setup','ready','in_service','breakdown','closed','cancelled')),
  service_start timestamptz not null,
  service_end timestamptz not null,
  guaranteed_guests integer not null default 0 check (guaranteed_guests >= 0),
  manager_name text not null default '',
  notes text not null default '',
  created_by uuid default auth.uid() references auth.users(id),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (service_end > service_start)
);
create index events_venue_id_start_idx on events(venue_id, service_start);

create table event_spaces (
  event_id uuid not null references events(id) on delete cascade,
  venue_space_id uuid not null references venue_spaces(id) on delete cascade,
  primary key (event_id, venue_space_id)
);

create table event_tasks (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  department text not null,
  title text not null,
  is_required boolean not null default true,
  status text not null default 'not_started' check (status in
    ('not_started','in_progress','completed','blocked')),
  due_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index event_tasks_event_id_idx on event_tasks(event_id);

create table audit_logs (
  id bigint generated always as identity primary key,
  venue_id uuid references venues(id) on delete cascade,
  actor_id uuid default auth.uid(),
  action text not null,
  entity text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_venue_id_created_idx on audit_logs(venue_id, created_at);

-- ---------------------------------------------------------------------------
-- Authorization helpers (security definer so policies do not recurse)
-- ---------------------------------------------------------------------------
create or replace function public.is_venue_member(p_venue uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from venue_memberships m
    where m.venue_id = p_venue and m.user_id = auth.uid() and m.status = 'active'
  );
$$;

create or replace function public.has_permission(p_venue uuid, p_permission text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from role_assignments ra
    join role_permissions rp on rp.role_code = ra.role_code
    join venue_memberships m on m.venue_id = ra.venue_id and m.user_id = ra.user_id
    where ra.venue_id = p_venue
      and ra.user_id = auth.uid()
      and m.status = 'active'
      and rp.permission_code = p_permission
  );
$$;

-- ---------------------------------------------------------------------------
-- Audit trigger for events
-- ---------------------------------------------------------------------------
create or replace function public.audit_event_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (
    new.venue_id,
    case when tg_op = 'INSERT' then 'event.created' else 'event.updated' end,
    'event',
    new.id,
    jsonb_build_object('status', new.status, 'previous_status', case when tg_op = 'UPDATE' then old.status end)
  );
  return new;
end;
$$;

create trigger events_audit
after insert or update on events
for each row execute function public.audit_event_change();

-- ---------------------------------------------------------------------------
-- Lifecycle transitions. Clients must use this function; direct status updates are revoked.
-- Draft → Planning → Approved → Setup → Ready → In Service → Breakdown → Closed
-- ---------------------------------------------------------------------------
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
  end if;

  update events
     set status = p_to, updated_at = now(), version = version + 1
   where id = ev.id
  returning * into ev;

  return ev;
end;
$$;

revoke execute on function public.transition_event(uuid, text) from public, anon;
grant execute on function public.transition_event(uuid, text) to authenticated;

-- Prevent direct status writes; status changes go through transition_event.
-- Table-level UPDATE is revoked first because a table grant overrides a column-level revoke.
revoke update on events from authenticated, anon;
grant update (name, event_type, service_start, service_end, guaranteed_guests, manager_name, notes, updated_at) on events to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table organizations enable row level security;
alter table venues enable row level security;
alter table user_profiles enable row level security;
alter table venue_memberships enable row level security;
alter table roles enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;
alter table role_assignments enable row level security;
alter table venue_spaces enable row level security;
alter table events enable row level security;
alter table event_spaces enable row level security;
alter table event_tasks enable row level security;
alter table audit_logs enable row level security;

create policy organizations_read on organizations for select to authenticated
  using (exists (select 1 from venues v where v.organization_id = organizations.id and public.is_venue_member(v.id)));

create policy venues_read on venues for select to authenticated
  using (public.is_venue_member(id));

create policy user_profiles_read_own on user_profiles for select to authenticated
  using (id = auth.uid());

create policy user_profiles_update_own on user_profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy venue_memberships_read on venue_memberships for select to authenticated
  using (public.is_venue_member(venue_id));

create policy roles_read on roles for select to authenticated using (true);
create policy permissions_read on permissions for select to authenticated using (true);
create policy role_permissions_read on role_permissions for select to authenticated using (true);

create policy role_assignments_read on role_assignments for select to authenticated
  using (public.is_venue_member(venue_id));

create policy venue_spaces_read on venue_spaces for select to authenticated
  using (public.is_venue_member(venue_id));

create policy events_read on events for select to authenticated
  using (public.is_venue_member(venue_id));

create policy events_insert on events for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events') and status = 'draft');

create policy events_update on events for update to authenticated
  using (public.has_permission(venue_id, 'manage_events'))
  with check (public.has_permission(venue_id, 'manage_events'));

create policy event_spaces_read on event_spaces for select to authenticated
  using (exists (select 1 from events e where e.id = event_id and public.is_venue_member(e.venue_id)));

create policy event_tasks_read on event_tasks for select to authenticated
  using (public.is_venue_member(venue_id));

create policy event_tasks_insert on event_tasks for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events'));

create policy event_tasks_update on event_tasks for update to authenticated
  using (public.has_permission(venue_id, 'update_tasks'))
  with check (public.has_permission(venue_id, 'update_tasks'));

create policy audit_logs_read on audit_logs for select to authenticated
  using (public.has_permission(venue_id, 'view_reports'));

-- Audit rows are written by triggers and security definer functions only.
-- Writes to role and membership tables are administrative and happen outside client access.
