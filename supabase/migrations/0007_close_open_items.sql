-- CUTX Premium Command: close the open items from docs/SECURITY_REVIEW.md.
-- 1. Department membership, checked by department-level dispatch.
-- 2. Server-side task status rules (set_task_status replaces direct writes).
-- 3. BEO approval notifies the people whose work changed.
-- 4. Venue-configurable escalation thresholds.
-- 5. Private evidence storage for inspection photos.

-- ---------------------------------------------------------------------------
-- 1. Department membership
-- ---------------------------------------------------------------------------
create table department_memberships (
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  department text not null check (department in ('suites','banquets','culinary','beverage','lounge','operations')),
  created_at timestamptz not null default now(),
  primary key (venue_id, user_id, department)
);
create index department_memberships_user_idx on department_memberships(user_id);

alter table department_memberships enable row level security;
create policy department_memberships_read on department_memberships for select to authenticated
  using (public.is_venue_member(venue_id));
create policy department_memberships_insert on department_memberships for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy department_memberships_delete on department_memberships for delete to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'));

create or replace function public.in_department(p_venue uuid, p_department text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from department_memberships
    where venue_id = p_venue and user_id = auth.uid() and department = p_department
  );
$$;

-- Dispatch: a department-level request can be worked only by someone in that department.
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
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  previous_status := r.status;
  if not public.is_venue_member(r.venue_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if r.version <> p_expected_version then
    raise exception 'Conflict: this request was changed by someone else. Refresh and try again.' using errcode = '40001';
  end if;
  if r.status in ('completed', 'rejected', 'cancelled') then
    raise exception 'This request is already %', r.status;
  end if;

  -- Managers are event managers (manage_events). Runners cannot reassign or cancel.
  is_manager := public.has_permission(r.venue_id, 'manage_events');
  -- Named person, or a department-level request the user's department covers.
  -- coalesce: a NULL comparison must count as "not assigned", not as "unknown" (which would pass IF NOT checks).
  is_assignee := coalesce(r.assigned_user_id = auth.uid(), false)
    or (r.assigned_user_id is null
        and r.assigned_department is not null
        and public.has_permission(r.venue_id, 'manage_requests')
        and public.in_department(r.venue_id, r.assigned_department));

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

-- ---------------------------------------------------------------------------
-- 2. Task status through a function, with the rules the lifecycle needs
-- ---------------------------------------------------------------------------
create or replace function public.set_task_status(p_task uuid, p_status text)
returns event_tasks
language plpgsql security definer set search_path = public
as $$
declare
  t event_tasks%rowtype;
begin
  select * into t from event_tasks where id = p_task for update;
  if not found then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;
  if not public.is_venue_member(t.venue_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if not public.has_permission(t.venue_id, 'update_tasks') then
    raise exception 'Not authorized to update tasks' using errcode = '42501';
  end if;
  if p_status not in ('not_started', 'in_progress', 'completed', 'blocked') then
    raise exception 'Unknown task status %', p_status;
  end if;

  -- Setting the same status again is a no-op, so repeated sends are safe.
  if t.status = p_status then
    return t;
  end if;

  -- A completed task can be reopened only by a manager.
  if t.status = 'completed' and not public.has_permission(t.venue_id, 'manage_events') then
    raise exception 'Only managers can reopen a completed task' using errcode = '42501';
  end if;

  -- A task changed by a BEO revision cannot be completed until its department acknowledges the change.
  if p_status = 'completed' and t.needs_review then
    raise exception 'This task changed with a BEO revision. Acknowledge the revision before completing it.';
  end if;

  update event_tasks set
    status = p_status,
    completed_at = case when p_status = 'completed' then now() else null end,
    completed_by = case when p_status = 'completed' then auth.uid() else null end,
    updated_at = now()
  where id = t.id
  returning * into t;

  return t;
end;
$$;

-- Clients no longer write task rows directly.
revoke update on event_tasks from authenticated, anon;

-- ---------------------------------------------------------------------------
-- 3. BEO approval notifies the people whose work changed
-- ---------------------------------------------------------------------------
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
  previous_approved := doc.current_revision_id;

  update beo_revisions set status = 'superseded' where beo_id = doc.id and status = 'approved';

  update beo_revisions
     set status = 'approved', approved_by = auth.uid(), approved_at = now()
   where id = r.id
  returning * into r;

  update beo_documents set current_revision_id = r.id where id = doc.id;

  select coalesce(array_agg(value::text), '{}') into affected
  from jsonb_array_elements_text(coalesce(r.content -> 'departments', '[]'::jsonb));

  -- Only revisions after the first approval change work already planned.
  if previous_approved is not null then
    update event_tasks
       set needs_review = true,
           review_reason = 'BEO revision ' || r.revision_no || ' changed this department''s work',
           updated_at = now()
     where event_id = doc.event_id
       and department = any(affected)
       and status <> 'completed';
    get diagnostics flagged = row_count;
  end if;

  -- Tell everyone rostered to an affected department, and everyone who belongs to one.
  insert into notifications (venue_id, user_id, kind, title, body, event_id)
  select distinct r.venue_id, people.user_id, 'beo_revision',
         case when previous_approved is null then 'BEO approved' else 'BEO revision approved' end,
         case when previous_approved is null
              then 'The BEO for this event is approved. Review your department section.'
              else 'Revision ' || r.revision_no || ' changed your department''s work. Review the flagged tasks.' end,
         doc.event_id
  from (
    select s.user_id from event_staff s
     where s.event_id = doc.event_id and s.department = any(affected) and s.user_id is not null
    union
    select m.user_id from department_memberships m
     where m.venue_id = r.venue_id and m.department = any(affected)
  ) people;

  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Venue-configurable escalation thresholds
-- ---------------------------------------------------------------------------
create table escalation_rules (
  venue_id uuid not null references venues(id) on delete cascade,
  priority text not null check (priority in ('low','normal','high','urgent')),
  minutes integer not null check (minutes > 0 and minutes <= 1440),
  primary key (venue_id, priority)
);

alter table escalation_rules enable row level security;
create policy escalation_rules_read on escalation_rules for select to authenticated
  using (public.is_venue_member(venue_id));
create policy escalation_rules_insert on escalation_rules for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy escalation_rules_update on escalation_rules for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));

-- ---------------------------------------------------------------------------
-- 5. Private evidence storage
-- ---------------------------------------------------------------------------
-- Object path convention: {venue_id}/{event_id}/{file}. Only members of that venue can read or write.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidence', 'evidence', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy evidence_read on storage.objects for select to authenticated
  using (
    bucket_id = 'evidence'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.is_venue_member(((storage.foldername(name))[1])::uuid)
             else false end
  );

create policy evidence_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'run_inspections')
             else false end
  );

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke execute on function public.in_department(uuid, text) from public, anon;
grant execute on function public.in_department(uuid, text) to authenticated;
revoke execute on function public.set_task_status(uuid, text) from public, anon;
grant execute on function public.set_task_status(uuid, text) to authenticated;
