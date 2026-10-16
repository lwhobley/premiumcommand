-- Run after migrations 0030 and 0031. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_other_venue uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_event uuid;
  v_club uuid;
  v_assignment uuid;
  v_state suite_event_assignments;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'clubs-director@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_manager, 'authenticated', 'authenticated', 'clubs-manager@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Clubs test');
  insert into public.venues (id, organization_id, name) values
    (v_venue, v_org, 'Clubs arena'), (v_other_venue, v_org, 'Other arena');
  insert into public.venue_memberships (venue_id, user_id) values (v_venue, v_director), (v_venue, v_manager);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_manager, 'premium_manager');
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_venue, 'Club night', 'concert', now() + interval '1 day', now() + interval '1 day 4 hours')
    returning id into v_event;

  -- Only administrators add spaces, clubs included.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.venue_suites (venue_id, name, map_area) values (v_venue, 'Manager club', 'club_a');
    raise exception 'A manager added a club';
  exception when insufficient_privilege then null;
  end;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.venue_suites (venue_id, name, map_area)
    values (v_venue, 'Premium Club A', 'club_a') returning id into v_club;

  -- A map position is used once per venue and must be a plain key.
  begin
    insert into public.venue_suites (venue_id, name, map_area) values (v_venue, 'Second club A', 'club_a');
    raise exception 'Two spaces took the same map position';
  exception when unique_violation then null;
  end;
  begin
    insert into public.venue_suites (venue_id, name, map_area) values (v_venue, 'Bad key', 'Club A!');
    raise exception 'A malformed map position was accepted';
  exception when check_violation then null;
  end;
  -- The arena floor is placed the same way.
  insert into public.venue_suites (venue_id, name, map_area) values (v_venue, 'Main Arena Floor', 'arena_floor');
  -- Suites without a map position are unaffected by the unique key.
  insert into public.venue_suites (venue_id, name) values (v_venue, 'Suite 201'), (v_venue, 'Suite 202');
  reset role;
  -- Another venue can use the same position.
  insert into public.venue_suites (venue_id, name, map_area) values (v_other_venue, 'Premium Club A', 'club_a');

  -- A club works like a suite for the event: assignment, setup states, and staff placement.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.suite_event_assignments (venue_id, event_id, suite_id)
    values (v_venue, v_event, v_club) returning id into v_assignment;
  v_state := public.set_suite_state(v_assignment, 'setup_in_progress', 1);
  if v_state.state <> 'setup_in_progress' then raise exception 'The club did not move to setup'; end if;
  insert into public.event_staff (venue_id, event_id, display_name, role_label, suite_assignment_id)
    values (v_venue, v_event, 'Club bartender', 'Bartender', v_assignment);
  reset role;
end;
$$;

rollback;
