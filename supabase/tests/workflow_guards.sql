-- Run after migration 0016. Every test row is rolled back.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_event uuid;
  v_suite uuid;
  v_director uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'workflow-director@example.invalid',
      '00000000-0000-0000-0000-000000000000'),
    (v_other, 'authenticated', 'authenticated', 'workflow-other@example.invalid',
      '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Workflow guard test');
  insert into public.venues (id, organization_id, name)
    values (v_venue, v_org, 'Workflow venue');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_other);
  insert into public.role_assignments (venue_id, user_id, role_code)
    values (v_venue, v_director, 'director');
  insert into public.events (venue_id, name, event_type, service_start, service_end, status)
    values (v_venue, 'Workflow event', 'concert', now(), now() + interval '3 hours', 'breakdown')
    returning id into v_event;
  insert into public.venue_suites (venue_id, name)
    values (v_venue, 'Test suite') returning id into v_suite;

  begin
    insert into public.event_closeouts
      (venue_id, event_id, manager_signed_by, director_signed_by)
    values (v_venue, v_event, v_director, v_director);
    raise exception 'Same person signed both closeout roles';
  exception when check_violation then null;
  end;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;

  begin
    insert into public.event_tasks (venue_id, event_id, department, title, status)
      values (v_venue, v_event, 'operations', 'Invalid task', 'completed');
    raise exception 'Completed task created';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%event_tasks%' then raise; end if;
  end;
  begin
    insert into public.suite_event_assignments
      (venue_id, event_id, suite_id, state)
    values (v_venue, v_event, v_suite, 'ready');
    raise exception 'Ready suite created';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%suite_event_assignments%' then raise; end if;
  end;
  begin
    insert into public.banquet_timeline_items
      (venue_id, event_id, title, scheduled_start, status)
    values (v_venue, v_event, 'Invalid item', now(), 'done');
    raise exception 'Completed timeline item created';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%banquet_timeline_items%' then raise; end if;
  end;
  begin
    insert into public.culinary_batches
      (venue_id, event_id, description, state)
    values (v_venue, v_event, 'Invalid batch', 'received');
    raise exception 'Received culinary batch created';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%culinary_batches%' then raise; end if;
  end;

  begin
    perform public.set_person_role(v_venue, v_director, 'director', false);
    raise exception 'Last director role removed';
  exception when others then
    if sqlerrm <> 'The venue must keep at least one active director' then raise; end if;
  end;
  if exists (
    select 1 from public.list_venue_members(v_venue)
    where display_name like '%@%'
  ) then
    raise exception 'Staff member list exposed an email address';
  end if;
  perform public.set_person_role(v_venue, v_other, 'director', true);
  perform public.set_person_role(v_venue, v_director, 'director', false);
  reset role;
  if (select count(*) from public.role_assignments
      where venue_id = v_venue and role_code = 'director') <> 1 then
    raise exception 'Director handoff did not leave exactly one director';
  end if;

  raise notice 'Workflow guard checks passed';
end;
$$;

rollback;
