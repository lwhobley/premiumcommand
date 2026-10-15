-- Run after migration 0024. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_event_a uuid;
  v_event_b uuid;
  v_staff_row uuid;
  v_beo_a uuid;
  v_n integer;
  v_ack timestamptz;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_manager, 'authenticated', 'authenticated', 'deploy-manager@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'deploy-runner@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_other, 'authenticated', 'authenticated', 'deploy-other@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Deployment test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Deployment arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_manager), (v_venue, v_runner), (v_venue, v_other);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_manager, 'premium_manager'), (v_venue, v_runner, 'runner'), (v_venue, v_other, 'runner');

  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_venue, 'Event A', 'concert', now(), now() + interval '3 hours') returning id into v_event_a;
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_venue, 'Event B', 'concert', now(), now() + interval '3 hours') returning id into v_event_b;
  insert into public.beo_documents (venue_id, event_id, title)
    values (v_venue, v_event_a, 'BEO A') returning id into v_beo_a;
  insert into public.beo_documents (venue_id, event_id, title)
    values (v_venue, v_event_b, 'BEO B');

  -- The manager assigns the runner to Event A. The runner gets a notice.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.event_staff (venue_id, event_id, display_name, role_label, department, user_id)
    values (v_venue, v_event_a, 'Runner', 'Runner', 'operations', v_runner)
    returning id into v_staff_row;
  reset role;

  select count(*) into v_n from public.notifications
   where user_id = v_runner and kind = 'assignment' and event_id = v_event_a;
  if v_n <> 1 then raise exception 'Expected one assignment notice, found %', v_n; end if;

  -- The runner sees the roster for the event (view_deployment), and their own assignment.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.event_staff where event_id = v_event_a;
  if v_n <> 1 then raise exception 'Runner cannot see the roster (found %)', v_n; end if;

  -- The runner cannot change assignments or availability.
  begin
    update public.event_staff set zone = 'Z9' where id = v_staff_row;
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'Runner changed an assignment'; end if;
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.staff_availability (venue_id, user_id, status, starts_at, ends_at)
      values (v_venue, v_runner, 'unavailable', now(), now() + interval '1 hour');
    raise exception 'Runner added availability';
  exception when insufficient_privilege or others then
    if sqlerrm = 'Runner added availability' then raise; end if;
  end;

  -- The runner acknowledges their own assignment.
  v_ack := public.acknowledge_assignment(v_staff_row);
  if v_ack is null then raise exception 'Acknowledgment not recorded'; end if;
  reset role;

  -- Someone else cannot acknowledge the runner's assignment.
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.acknowledge_assignment(v_staff_row);
    raise exception 'Another person acknowledged the assignment';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- The runner sees only the BEO for Event A, the event they are assigned to.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.beo_documents;
  if v_n <> 1 then raise exception 'Runner sees % BEOs, expected 1', v_n; end if;
  reset role;

  -- Moving the runner to another person clears their acknowledgment and notifies both people.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update public.event_staff set user_id = v_other, zone = 'Z2' where id = v_staff_row;
  reset role;

  if (select acknowledged_at from public.event_staff where id = v_staff_row) is not null then
    raise exception 'Acknowledgment survived a reassignment';
  end if;
  select count(*) into v_n from public.notifications
   where user_id = v_runner and title = 'Assignment removed';
  if v_n <> 1 then raise exception 'Former assignee was not told (found %)', v_n; end if;
  select count(*) into v_n from public.notifications
   where user_id = v_other and kind = 'assignment';
  if v_n < 1 then raise exception 'New assignee was not told'; end if;

  raise notice 'Deployment and assignment checks passed';
end;
$$;

rollback;
