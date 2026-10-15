-- Run after migration 0012. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_count integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'suite-director@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'suite-runner@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Suite count test');
  insert into public.venues (id, organization_id, name) values
    (v_venue, v_org, 'Test arena'),
    (v_other, v_org, 'Other arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_runner);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_runner, 'runner');

  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_count := public.set_service_suite_count(v_venue, 26);
  reset role;
  if v_count <> 26 or (select service_suite_count from public.venues where id = v_venue) <> 26 then
    raise exception 'Director count update failed';
  end if;
  if (select count(*) from public.venue_suites where venue_id = v_venue) <> 0 then
    raise exception 'Count update fabricated suite profiles';
  end if;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.set_service_suite_count(v_venue, 27);
    reset role;
    raise exception 'Runner changed the count';
  exception when insufficient_privilege then
    reset role;
  end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.set_service_suite_count(v_other, 26);
    reset role;
    raise exception 'Director changed another venue';
  exception when insufficient_privilege then
    reset role;
  end;

  if (select service_suite_count from public.venues where id = v_venue) <> 26 then
    raise exception 'Unauthorized attempt changed the count';
  end if;
  raise notice 'Suite count checks passed';
end;
$$;

rollback;
