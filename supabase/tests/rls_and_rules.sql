-- CUTX Premium Command: isolation and workflow-rule checks.
-- Run against a database where migrations 0001 to 0007 are applied. Everything runs inside
-- one transaction that ends by raising an error, so no data is left behind.
-- The final message "ALL CHECKS PASSED" means every check held.

do $$
declare
  u_dir uuid := gen_random_uuid();
  u_run uuid := gen_random_uuid();
  u_suite uuid := gen_random_uuid();
  u_other uuid := gen_random_uuid();
  v uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  o uuid := gen_random_uuid();
  ev uuid;
  ev_other uuid;
  req service_requests;
  t event_tasks;
  rev_id uuid;
  v_beo uuid;
  n int;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (u_dir, 'authenticated', 'authenticated', 'dir-chk@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (u_run, 'authenticated', 'authenticated', 'run-chk@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (u_suite, 'authenticated', 'authenticated', 'suite-chk@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (u_other, 'authenticated', 'authenticated', 'other-chk@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into organizations (id, name) values (o, 'chk-org');
  insert into venues (id, organization_id, name) values (v, o, 'chk-venue'), (v_other, o, 'chk-other');
  insert into venue_memberships (venue_id, user_id) values
    (v, u_dir), (v, u_run), (v, u_suite), (v_other, u_other);
  insert into role_assignments (venue_id, user_id, role_code) values
    (v, u_dir, 'director'), (v, u_run, 'runner'), (v, u_suite, 'suite_attendant'), (v_other, u_other, 'director');
  insert into department_memberships (venue_id, user_id, department) values (v, u_suite, 'suites');

  insert into events (venue_id, name, event_type, service_start, service_end, status)
    values (v, 'chk-event', 'concert', now(), now() + interval '3 hours', 'in_service') returning id into ev;
  insert into events (venue_id, name, event_type, service_start, service_end, status)
    values (v_other, 'other-event', 'concert', now(), now() + interval '3 hours', 'in_service') returning id into ev_other;

  -- 1. Cross-tenant isolation: a member of another venue cannot see this event.
  perform set_config('request.jwt.claims', json_build_object('sub', u_other, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from events where id = ev;
  reset role;
  if n <> 0 then raise exception '1 FAILED: cross-tenant event visible'; end if;

  -- 2. Tasks: generated, then status set only through set_task_status.
  perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform generate_event_tasks(ev);
  reset role;
  select * into t from event_tasks where event_id = ev and department = 'culinary' and template_id is not null limit 1;

  -- 2a. Direct update of a task row is refused.
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
    set local role authenticated;
    update event_tasks set status = 'completed' where id = t.id;
    reset role;
    raise exception '2a FAILED: direct task update allowed';
  exception when others then
    reset role;
    if sqlerrm like '2a FAILED%' then raise; end if;
  end;

  -- 2b. A BEO revision flags the culinary task; completion is blocked until acknowledged.
  perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_beo := (create_beo(ev, 'chk-beo', '{"departments":["culinary"],"guests":10}'::jsonb, 'v1')).id;
  select id into rev_id from beo_revisions where beo_id = v_beo and revision_no = 1;
  perform approve_beo_revision(rev_id);
  perform propose_beo_revision(v_beo, '{"departments":["culinary"],"guests":12}'::jsonb, 'guests', 1);
  select id into rev_id from beo_revisions where beo_id = v_beo and revision_no = 2;
  perform approve_beo_revision(rev_id);
  reset role;
  if not (select needs_review from event_tasks where id = t.id) then
    raise exception '2b FAILED: BEO revision did not flag the culinary task';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform set_task_status(t.id, 'completed');
    reset role;
    raise exception '2c FAILED: completed while flagged for review';
  exception when others then
    reset role;
    if sqlerrm like '2c FAILED%' then raise; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
    set local role authenticated;
  end;
  perform acknowledge_beo_revision(rev_id, 'culinary');
  perform set_task_status(t.id, 'completed');
  -- Repeating the same status is a no-op.
  perform set_task_status(t.id, 'completed');
  reset role;
  if (select status from event_tasks where id = t.id) <> 'completed' then
    raise exception '2d FAILED: task not completed after acknowledgment';
  end if;

  -- 2e. The approval notified the culinary staff who belong to the department.
  select count(*) into n from notifications where kind = 'beo_revision' and event_id = ev;
  if n < 1 then raise exception '2e FAILED: no BEO notification for the department'; end if;

  -- 3. Department-level dispatch: only the matching department can work it.
  perform set_config('request.jwt.claims', json_build_object('sub', u_dir, 'role', 'authenticated')::text, true);
  set local role authenticated;
  req := create_service_request(ev, gen_random_uuid(), 'ice', 'Suite 3', 'Two bags of ice', 'high');
  req := transition_service_request(req.id, 'assigned', req.version, '', 'suites', null);
  reset role;

  -- 3a. A runner (operations, not suites) cannot accept a suites request.
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', u_run, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform transition_service_request(req.id, 'accepted', req.version);
    reset role;
    raise exception '3a FAILED: runner accepted a suites request';
  exception when others then
    reset role;
    if sqlerrm like '3a FAILED%' then raise; end if;
  end;

  -- 3b. A suites member can accept it.
  perform set_config('request.jwt.claims', json_build_object('sub', u_suite, 'role', 'authenticated')::text, true);
  set local role authenticated;
  req := transition_service_request(req.id, 'accepted', req.version);
  reset role;
  if req.status <> 'accepted' then raise exception '3b FAILED: %', req.status; end if;

  -- 4. Runner cannot cancel (manager-only).
  perform set_config('request.jwt.claims', json_build_object('sub', u_run, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform transition_service_request(req.id, 'cancelled', req.version, 'test');
    reset role;
    raise exception '4 FAILED: runner cancelled';
  exception when others then
    reset role;
    if sqlerrm like '4 FAILED%' then raise; end if;
  end;

  raise exception 'ALL CHECKS PASSED - rolled back, no data persisted';
end $$;
