-- CUTX Premium Command: runner and guest service.
-- Guest preference cards per suite, comps that a manager or admin must approve, and runner
-- location points that are only accepted while the runner has a request in progress.

-- Preference card: one per suite assignment (guest preferences that travel with the suite).
create table guest_preferences (
  suite_assignment_id uuid primary key references suite_event_assignments(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  seating text not null default '' check (length(seating) <= 200),
  drink text not null default '' check (length(drink) <= 200),
  allergies text not null default '' check (length(allergies) <= 500),
  notes text not null default '' check (length(notes) <= 1000),
  updated_by uuid default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table guest_preferences enable row level security;

create policy guest_preferences_read on guest_preferences
  for select using (is_venue_member(venue_id));

create policy guest_preferences_write on guest_preferences
  for all using (has_permission(venue_id, 'manage_requests'))
  with check (has_permission(venue_id, 'manage_requests'));

-- Comps: a discount or complimentary item that is requested by staff and decided by a manager.
create table comps (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  suite_assignment_id uuid references suite_event_assignments(id) on delete set null,
  amount_cents integer not null check (amount_cents > 0 and amount_cents <= 1000000),
  reason text not null check (length(trim(reason)) > 0 and length(reason) <= 500),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid not null default auth.uid() references auth.users(id),
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  decision_note text not null default '' check (length(decision_note) <= 500),
  version integer not null default 1
);

create index comps_event_status_idx on comps(event_id, status);

alter table comps enable row level security;

-- Staff who can take service requests can see and raise comps; only managers and admins decide.
create policy comps_read on comps
  for select using (is_venue_member(venue_id));

create policy comps_insert on comps
  for insert with check (is_venue_member(venue_id) and requested_by = auth.uid() and status = 'pending');

-- Decisions go through decide_comp(), which checks the approver's role.
create or replace function public.decide_comp(
  p_comp uuid,
  p_decision text,
  p_expected_version integer,
  p_note text default ''
)
returns comps
language plpgsql security definer set search_path = public
as $$
declare
  c comps%rowtype;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'Choose approved or rejected.' using errcode = '22023';
  end if;
  select * into c from comps where id = p_comp for update;
  if not found then
    raise exception 'Comp not found' using errcode = 'P0002';
  end if;
  if not (has_permission(c.venue_id, 'manage_events') or has_permission(c.venue_id, 'manage_configuration')) then
    raise exception 'Only a manager or administrator can approve comps.' using errcode = '42501';
  end if;
  if c.version <> p_expected_version then
    raise exception 'This comp was changed by someone else. Refresh and try again.' using errcode = '40001';
  end if;
  if c.status <> 'pending' then
    raise exception 'This comp is already %.', c.status using errcode = '22023';
  end if;
  update comps
     set status = p_decision, decided_by = auth.uid(), decided_at = now(),
         decision_note = coalesce(p_note, ''), version = version + 1
   where id = p_comp
   returning * into c;
  return c;
end;
$$;

revoke all on function public.decide_comp(uuid, text, integer, text) from public, anon;
grant execute on function public.decide_comp(uuid, text, integer, text) to authenticated;

-- Runner location: recorded only while the runner has a request in progress for that event.
create table runner_locations (
  id bigint generated always as identity primary key,
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  request_id uuid not null references service_requests(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision check (accuracy_m is null or accuracy_m >= 0),
  recorded_at timestamptz not null default now()
);

create index runner_locations_request_idx on runner_locations(request_id, recorded_at desc);

alter table runner_locations enable row level security;

-- Managers see locations for requests they can work; the runner sees only their own points.
create policy runner_locations_read on runner_locations
  for select using (
    user_id = auth.uid() or has_permission(venue_id, 'manage_requests')
  );

-- A point is accepted only for the runner's own request, while that request is in progress.
create policy runner_locations_insert on runner_locations
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from service_requests r
       where r.id = request_id
         and r.venue_id = runner_locations.venue_id
         and r.event_id = runner_locations.event_id
         and r.assigned_user_id = auth.uid()
         and r.status = 'in_progress'
    )
  );

-- Location points are kept only for the life of the request: removed once it is no longer in progress.
create or replace function public.clear_runner_locations()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status <> 'in_progress' and old.status = 'in_progress' then
    delete from runner_locations where request_id = new.id;
  end if;
  return new;
end;
$$;

create trigger service_requests_clear_locations
  after update of status on service_requests
  for each row execute function public.clear_runner_locations();
