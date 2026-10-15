-- Run after migration 0020. Every test row is rolled back.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_space uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_function text;
  v_role text;
  v_rows integer;
begin
  foreach v_function in array array[
    'public.check_inspection_response_item()',
    'public.check_inspection_template_venue()',
    'public.create_user_profile()',
    'public.guard_closeout_lifecycle()'
  ] loop
    foreach v_role in array array['anon', 'authenticated'] loop
      if has_function_privilege(v_role, v_function, 'execute') then
        raise exception '% can execute %', v_role, v_function;
      end if;
    end loop;
  end loop;

  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and tablename = 'venue_space_floor_plans'
                and cmd = 'ALL') then
    raise exception 'A FOR ALL floor-plan policy remains';
  end if;

  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'advisor-director@example.invalid',
      '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'advisor-runner@example.invalid',
      '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Advisor hardening test');
  insert into public.venues (id, organization_id, name)
    values (v_venue, v_org, 'Advisor venue');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_runner);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_runner, 'runner');
  insert into public.venue_spaces (id, venue_id, name, space_type)
    values (v_space, v_venue, 'Advisor room', 'banquet');

  -- A runner can read but not write floor plans.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.venue_space_floor_plans
      (venue_id, venue_space_id, width_feet, depth_feet)
    values (v_venue, v_space, 40, 30);
    raise exception 'Runner created a floor plan';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%venue_space_floor_plans%' then raise; end if;
  end;
  reset role;

  -- A director can upsert the way the app does.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.venue_space_floor_plans
    (venue_id, venue_space_id, width_feet, depth_feet)
  values (v_venue, v_space, 40, 30);
  insert into public.venue_space_floor_plans
    (venue_id, venue_space_id, width_feet, depth_feet)
  values (v_venue, v_space, 50, 30)
  on conflict (venue_space_id) do update set width_feet = excluded.width_feet;
  reset role;
  if (select width_feet from public.venue_space_floor_plans
       where venue_space_id = v_space) <> 50 then
    raise exception 'Director upsert did not update the floor plan';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if (select count(*) from public.venue_space_floor_plans
       where venue_space_id = v_space) <> 1 then
    raise exception 'Runner cannot read the floor plan';
  end if;
  update public.venue_space_floor_plans set width_feet = 60
   where venue_space_id = v_space;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'Runner updated a floor plan'; end if;
  delete from public.venue_space_floor_plans where venue_space_id = v_space;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'Runner deleted a floor plan'; end if;
  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  delete from public.venue_space_floor_plans where venue_space_id = v_space;
  get diagnostics v_rows = row_count;
  reset role;
  if v_rows <> 1 then raise exception 'Director could not delete the floor plan'; end if;

  raise notice 'Advisor hardening checks passed';
end;
$$;

rollback;
