-- Run after migration 0023. The transaction rolls back all test rows.
-- The PIN fingerprints here are placeholders: the edge functions compute real ones with a secret.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_staff_a uuid := gen_random_uuid();
  v_staff_b uuid := gen_random_uuid();
  v_profile_a uuid;
  v_profile_b uuid;
  v_profile_admin uuid;
  v_fields_a jsonb := '{"employee_id":"E-1001","full_name":"Ana Staff","department":"suites"}';
  v_fields_b jsonb := '{"employee_id":"E-1002","full_name":"Ben Staff","department":"operations"}';
  v_fp_a text := repeat('a', 64);
  v_fp_b text := repeat('b', 64);
  v_fp_admin text := repeat('c', 64);
  n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_admin, 'authenticated', 'authenticated', 'staff-admin@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_staff_a, 'authenticated', 'authenticated', 'staff-a@staff.cutx.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_staff_b, 'authenticated', 'authenticated', 'staff-b@staff.cutx.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Staff account test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Staff arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_admin), (v_venue, v_staff_a), (v_venue, v_staff_b);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_admin, 'director'), (v_venue, v_staff_a, 'runner'), (v_venue, v_staff_b, 'runner');

  -- Administrator creates two staff profiles.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_profile_a := public.staff_create_profile(v_venue, v_staff_a, v_fields_a, array['runner'], v_fp_a);
  v_profile_b := public.staff_create_profile(v_venue, v_staff_b, v_fields_b, array['runner'], v_fp_b);
  -- The administrator also has a staff profile, so the self-deactivation rule can be tested.
  v_profile_admin := public.staff_create_profile(v_venue, v_admin, '{"employee_id":"E-1000","full_name":"Ada Admin"}', array['runner'], v_fp_admin);
  reset role;

  -- A second staff member cannot reuse the same PIN at the venue.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.staff_set_pin(v_profile_b, v_fp_a);
    raise exception 'Duplicate PIN accepted';
  exception when unique_violation then
    null;
  end;
  reset role;

  -- Bad field values are refused.
  begin
    perform public.staff_check_fields('{"employee_id":"x y","full_name":"Bad"}');
    raise exception 'Invalid employee ID accepted';
  exception when invalid_parameter_value then
    null;
  end;
  begin
    perform public.staff_check_fields('{"employee_id":"E-9","full_name":"Bad","role":"director"}');
    raise exception 'Unknown field accepted';
  exception when invalid_parameter_value then
    null;
  end;

  -- The director role cannot be given through staff creation.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.staff_create_profile(v_venue, v_staff_b, '{"employee_id":"E-1003","full_name":"X"}', array['director'], v_fp_b);
    raise exception 'Director role granted through staff creation';
  exception when invalid_parameter_value then
    null;
  end;
  reset role;

  -- A staff member sees only their own profile.
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.staff_profiles;
  if n <> 1 then raise exception 'Staff saw % profiles, expected 1', n; end if;
  -- And cannot change anything, including their own details.
  begin
    perform public.staff_update_profile(v_profile_a, v_fields_a, 1);
    raise exception 'Staff edited a profile';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- Staff cannot read PIN rows at all.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    select count(*) into n from public.staff_pins;
    raise exception 'Client read PIN rows';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- Deactivation suspends membership, which blocks access on the next request.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.staff_set_status(v_profile_a, false);
  reset role;
  if (select status from public.venue_memberships where venue_id = v_venue and user_id = v_staff_a) <> 'suspended' then
    raise exception 'Deactivation did not suspend membership';
  end if;

  -- An administrator cannot deactivate their own account.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.staff_set_status((select id from public.staff_profiles where user_id = v_admin), false);
    raise exception 'Self deactivation allowed';
  exception when raise_exception then
    null;
  end;
  reset role;

  -- Audit trail records the administrator actions.
  select count(*) into n from public.audit_logs
   where venue_id = v_venue and action in ('staff.created', 'staff.deactivated');
  if n < 3 then raise exception 'Audit log missing staff actions (found %)', n; end if;

  raise notice 'Staff account checks passed';
end;
$$;

rollback;
