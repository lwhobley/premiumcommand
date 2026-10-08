-- CUTX Premium Command: Phase 2 live service dispatch.
-- Service requests, their history, idempotent creation, and a guarded state machine.

create table service_requests (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  client_request_id uuid not null,
  category text not null check (category in (
    'food_delivery','beverage_replenishment','ice','glassware','equipment','room_setup',
    'cleanup','guest_assistance','maintenance','culinary_support','management_assistance','other')),
  location text not null default '',
  description text not null check (length(trim(description)) > 0),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'new' check (status in
    ('new','assigned','accepted','in_progress','blocked','completed','rejected','cancelled')),
  assigned_department text,
  assigned_user_id uuid references auth.users(id),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  completed_at timestamptz,
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  unique (venue_id, client_request_id)
);
create index service_requests_event_status_idx on service_requests(event_id, status);

create table service_request_history (
  id bigint generated always as identity primary key,
  request_id uuid not null references service_requests(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  from_status text,
  to_status text not null,
  actor_id uuid default auth.uid(),
  note text not null default '',
  created_at timestamptz not null default now()
);
create index service_request_history_request_idx on service_request_history(request_id);

-- Idempotent create: a retry with the same client_request_id returns the original row.
create or replace function public.create_service_request(
  p_event uuid,
  p_client_request_id uuid,
  p_category text,
  p_location text,
  p_description text,
  p_priority text
)
returns service_requests
language plpgsql security definer set search_path = public
as $$
declare
  ev events%rowtype;
  existing service_requests%rowtype;
  r service_requests%rowtype;
begin
  select * into ev from events where id = p_event;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(ev.venue_id, 'manage_requests') then
    raise exception 'Not authorized to create service requests' using errcode = '42501';
  end if;

  select * into existing from service_requests
   where venue_id = ev.venue_id and client_request_id = p_client_request_id;
  if found then
    if existing.event_id <> p_event then
      raise exception 'Client request id already used for another event' using errcode = '23505';
    end if;
    return existing;
  end if;

  if ev.status in ('closed', 'cancelled') then
    raise exception 'This event is not accepting service requests';
  end if;

  insert into service_requests (venue_id, event_id, client_request_id, category, location, description, priority)
  values (ev.venue_id, ev.id, p_client_request_id, p_category, coalesce(p_location, ''), p_description, coalesce(p_priority, 'normal'))
  returning * into r;

  insert into service_request_history (request_id, venue_id, from_status, to_status, note)
  values (r.id, r.venue_id, null, 'new', 'Created');

  return r;
end;
$$;

-- Guarded state machine with optimistic concurrency (p_expected_version).
-- Assign and cancel are manager-only (manage_events). Work actions are for the assignee or operators.
--   new/blocked/assigned/accepted --assign (manager)--> assigned
--   assigned --accept--> accepted --start--> in_progress --complete--> completed
--   assigned/accepted/in_progress --block (note)--> blocked
--   new/assigned/accepted --reject (note)--> rejected
--   any open state --cancel (manager, note)--> cancelled
-- completed, rejected and cancelled are terminal.
create or replace function public.transition_service_request(
  p_request uuid,
  p_to text,
  p_expected_version integer,
  p_note text default '',
  p_department text default null,
  p_user uuid default null
)
returns service_requests
language plpgsql security definer set search_path = public
as $$
declare
  r service_requests%rowtype;
  previous_status text;
  is_manager boolean;
  is_assignee boolean;
begin
  select * into r from service_requests where id = p_request for update;
  previous_status := r.status;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if not public.is_venue_member(r.venue_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if r.version <> p_expected_version then
    raise exception 'Conflict: this request was changed by someone else. Refresh and try again.' using errcode = '40001';
  end if;
  if r.status in ('completed', 'rejected', 'cancelled') then
    raise exception 'This request is already %', r.status;
  end if;

  -- Managers are event managers (manage_events). Runners hold manage_requests but cannot reassign or cancel.
  is_manager := public.has_permission(r.venue_id, 'manage_events');
  -- Department-level requests (no named person) can be worked by any request-capable staff member.
  is_assignee := r.assigned_user_id = auth.uid()
    or (r.assigned_user_id is null and public.has_permission(r.venue_id, 'manage_requests'));

  if p_to = 'assigned' then
    if not is_manager then raise exception 'Only managers can assign requests' using errcode = '42501'; end if;
    if r.status not in ('new', 'assigned', 'accepted', 'blocked') then
      raise exception 'Cannot assign a request that is %', r.status;
    end if;
    if p_department is null and p_user is null then
      raise exception 'Assignment needs a department or a person';
    end if;
  elsif p_to = 'accepted' then
    if r.status <> 'assigned' then raise exception 'Only assigned requests can be accepted'; end if;
    if not (is_manager or is_assignee) then raise exception 'Not authorized to accept' using errcode = '42501'; end if;
  elsif p_to = 'in_progress' then
    if r.status <> 'accepted' then raise exception 'Only accepted requests can be started'; end if;
    if not (is_manager or is_assignee) then raise exception 'Not authorized to start' using errcode = '42501'; end if;
  elsif p_to = 'completed' then
    if r.status <> 'in_progress' then raise exception 'Only requests in progress can be completed'; end if;
    if not (is_manager or is_assignee) then raise exception 'Not authorized to complete' using errcode = '42501'; end if;
  elsif p_to = 'blocked' then
    if r.status not in ('assigned', 'accepted', 'in_progress') then raise exception 'Cannot block a request that is %', r.status; end if;
    if length(trim(coalesce(p_note, ''))) = 0 then raise exception 'A reason is required to block a request'; end if;
    if not (is_manager or is_assignee) then raise exception 'Not authorized to block' using errcode = '42501'; end if;
  elsif p_to = 'rejected' then
    if r.status not in ('new', 'assigned', 'accepted') then raise exception 'Cannot reject a request that is %', r.status; end if;
    if length(trim(coalesce(p_note, ''))) = 0 then raise exception 'A reason is required to reject a request'; end if;
    if not (is_manager or is_assignee) then raise exception 'Not authorized to reject' using errcode = '42501'; end if;
  elsif p_to = 'cancelled' then
    if not is_manager then raise exception 'Only managers can cancel requests' using errcode = '42501'; end if;
    if length(trim(coalesce(p_note, ''))) = 0 then raise exception 'A reason is required to cancel a request'; end if;
  else
    raise exception 'Unknown target status %', p_to;
  end if;

  update service_requests set
    status = p_to,
    assigned_department = case when p_to = 'assigned' then coalesce(p_department, assigned_department) else assigned_department end,
    assigned_user_id = case when p_to = 'assigned' then p_user else assigned_user_id end,
    acknowledged_at = case when p_to = 'accepted' then now() else acknowledged_at end,
    completed_at = case when p_to = 'completed' then now() else completed_at end,
    version = version + 1,
    updated_at = now()
  where id = r.id
  returning * into r;

  insert into service_request_history (request_id, venue_id, from_status, to_status, note)
  values (r.id, r.venue_id, previous_status, p_to, coalesce(p_note, ''));

  return r;
end;
$$;

revoke execute on function public.create_service_request(uuid, uuid, text, text, text, text) from public, anon;
revoke execute on function public.transition_service_request(uuid, text, integer, text, text, uuid) from public, anon;
grant execute on function public.create_service_request(uuid, uuid, text, text, text, text) to authenticated;
grant execute on function public.transition_service_request(uuid, text, integer, text, text, uuid) to authenticated;

-- Clients read requests directly and write only through the functions above.
revoke insert, update, delete on service_requests from authenticated, anon;
revoke insert, update, delete on service_request_history from authenticated, anon;

alter table service_requests enable row level security;
alter table service_request_history enable row level security;

create policy service_requests_read on service_requests for select to authenticated
  using (public.is_venue_member(venue_id));

create policy service_request_history_read on service_request_history for select to authenticated
  using (public.is_venue_member(venue_id));

-- Realtime feed for live dispatch boards.
alter publication supabase_realtime add table service_requests;
