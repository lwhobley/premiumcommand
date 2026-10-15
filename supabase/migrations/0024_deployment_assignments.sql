-- Phase 2: staff deployment, availability, assignment notices, acknowledgments, and BEO access.
--
-- Staff can see the roster, the directory, availability, and their own assignments (read-only).
-- Only people with deploy_staff change assignments or availability. Staff acknowledge their own
-- assignment through acknowledge_assignment. A staff member sees a BEO only for an event they are
-- assigned to, unless their role already works on events (managers, approvers, banquet and culinary).

-- ---- 1. view_deployment ----------------------------------------------------

insert into permissions (code, description)
values ('view_deployment', 'View the staff roster, directory, availability, and assignments')
on conflict (code) do nothing;

insert into role_permissions (role_code, permission_code)
select r, 'view_deployment'
  from unnest(array['director', 'premium_manager', 'banquet_captain', 'suite_attendant',
                    'runner', 'culinary_lead', 'beverage_lead']) as r
on conflict do nothing;

drop policy event_staff_read on event_staff;
create policy event_staff_read on event_staff for select to authenticated
  using (
    public.has_permission(venue_id, 'deploy_staff')
    or public.has_permission(venue_id, 'view_deployment')
    or user_id = (select auth.uid())
  );

-- ---- 2. Assignment acknowledgments and notices -----------------------------

alter table event_staff add column acknowledged_at timestamptz;

-- Any change to who or where a person is assigned needs a fresh acknowledgment.
create or replace function public.event_staff_assignment_reset()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.suite_assignment_id is distinct from old.suite_assignment_id
     or new.department is distinct from old.department
     or new.zone is distinct from old.zone
     or new.station is distinct from old.station
     or new.role_label is distinct from old.role_label then
    new.acknowledged_at := null;
  end if;
  return new;
end;
$$;

create trigger event_staff_assignment_reset_trg
before update on event_staff
for each row execute function public.event_staff_assignment_reset();

-- Human-readable location: the premium space if any, then department, zone, and station.
create or replace function public.assignment_location(p_staff event_staff)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce(
    nullif(concat_ws(' · ',
      (select v.name
         from suite_event_assignments sa
         join venue_suites v on v.id = sa.suite_id
        where sa.id = p_staff.suite_assignment_id),
      nullif(p_staff.department, ''),
      nullif(p_staff.zone, ''),
      nullif(p_staff.station, '')), ''),
    'Location to be confirmed');
$$;

create or replace function public.event_staff_assignment_notify()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  event_name text;
  place text;
  role_text text;
begin
  select name into event_name from events where id = new.event_id;
  place := public.assignment_location(new);
  role_text := coalesce(nullif(new.role_label, ''), 'Position');

  if tg_op = 'INSERT' and new.user_id is not null then
    insert into notifications (venue_id, user_id, kind, title, body, event_id)
    values (new.venue_id, new.user_id, 'assignment', 'New assignment',
            coalesce(event_name, 'Event') || ': ' || role_text || ' · ' || place, new.event_id);
  elsif tg_op = 'UPDATE' then
    if old.user_id is not null and new.user_id is distinct from old.user_id then
      insert into notifications (venue_id, user_id, kind, title, body, event_id)
      values (new.venue_id, old.user_id, 'assignment', 'Assignment removed',
              'You were taken off ' || coalesce(event_name, 'an event') || '.', new.event_id);
    end if;
    if new.user_id is not null and (
         new.user_id is distinct from old.user_id
         or new.suite_assignment_id is distinct from old.suite_assignment_id
         or new.department is distinct from old.department
         or new.zone is distinct from old.zone
         or new.station is distinct from old.station
         or new.role_label is distinct from old.role_label) then
      insert into notifications (venue_id, user_id, kind, title, body, event_id)
      values (new.venue_id, new.user_id, 'assignment',
              case when new.user_id is distinct from old.user_id then 'New assignment' else 'Assignment changed' end,
              coalesce(event_name, 'Event') || ': ' || role_text || ' · ' || place
              || '. Please acknowledge in My Shift.', new.event_id);
    end if;
  end if;
  return new;
end;
$$;

create trigger event_staff_assignment_notify_trg
after insert or update on event_staff
for each row execute function public.event_staff_assignment_notify();

-- A person acknowledges only their own assignment. Repeat calls keep the first time.
create or replace function public.acknowledge_assignment(p_staff uuid)
returns timestamptz
language plpgsql security definer set search_path = public
as $$
declare
  acknowledged timestamptz;
begin
  update event_staff
     set acknowledged_at = coalesce(acknowledged_at, now())
   where id = p_staff and user_id = (select auth.uid())
  returning acknowledged_at into acknowledged;

  if acknowledged is null then
    raise exception 'That assignment is not yours' using errcode = '42501';
  end if;
  return acknowledged;
end;
$$;

revoke execute on function public.acknowledge_assignment(uuid) from public, anon;
grant execute on function public.acknowledge_assignment(uuid) to authenticated;

-- ---- 3. Availability -------------------------------------------------------

create table staff_availability (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('available', 'limited', 'unavailable')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  note text not null default '' check (length(note) <= 200),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index staff_availability_venue_idx on staff_availability(venue_id, starts_at);

alter table staff_availability enable row level security;
grant select, insert, update, delete on staff_availability to authenticated;

create policy staff_availability_read on staff_availability for select to authenticated
  using (
    public.has_permission(venue_id, 'deploy_staff')
    or public.has_permission(venue_id, 'view_deployment')
    or user_id = (select auth.uid())
  );

create policy staff_availability_write on staff_availability for all to authenticated
  using (public.has_permission(venue_id, 'deploy_staff'))
  with check (public.has_permission(venue_id, 'deploy_staff'));

-- ---- 4. Directory ----------------------------------------------------------
-- Names, employee IDs, departments, and titles only. Contact details and emergency contacts
-- stay with the profile, which only administrators and the person can read.

create or replace function public.staff_directory(p_venue uuid)
returns table (
  user_id uuid,
  full_name text,
  employee_id text,
  department text,
  job_title text,
  status text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not (public.has_permission(p_venue, 'view_deployment')
          or public.has_permission(p_venue, 'deploy_staff')) then
    raise exception 'Not authorized to view the staff directory' using errcode = '42501';
  end if;
  return query
  select s.user_id, s.full_name, s.employee_id, s.department, s.job_title, s.status
    from staff_profiles s
   where s.venue_id = p_venue
   order by s.full_name;
end;
$$;

revoke execute on function public.staff_directory(uuid) from public, anon;
grant execute on function public.staff_directory(uuid) to authenticated;

-- ---- 5. BEO access ---------------------------------------------------------

create or replace function public.beo_visible_to_me(p_venue uuid, p_event uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.has_permission(p_venue, 'manage_events')
      or public.has_permission(p_venue, 'approve_beo')
      or public.has_permission(p_venue, 'deploy_staff')
      or public.has_permission(p_venue, 'manage_banquets')
      or public.has_permission(p_venue, 'view_culinary')
      or exists (
        select 1 from event_staff s
         where s.venue_id = p_venue
           and s.event_id = p_event
           and s.user_id = (select auth.uid()));
$$;

revoke execute on function public.beo_visible_to_me(uuid, uuid) from public, anon;
grant execute on function public.beo_visible_to_me(uuid, uuid) to authenticated;

drop policy beo_documents_read on beo_documents;
create policy beo_documents_read on beo_documents for select to authenticated
  using (public.is_venue_member(venue_id) and public.beo_visible_to_me(venue_id, event_id));

drop policy beo_revisions_read on beo_revisions;
create policy beo_revisions_read on beo_revisions for select to authenticated
  using (exists (
    select 1 from beo_documents d
     where d.id = beo_revisions.beo_id));
