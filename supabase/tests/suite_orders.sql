-- Run after migration 0022. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_event uuid;
  v_suite uuid;
  v_assignment uuid;
  v_order public.suite_orders;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_manager, 'authenticated', 'authenticated', 'order-manager@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'order-runner@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Suite order test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Order arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_manager), (v_venue, v_runner);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_manager, 'premium_manager'), (v_venue, v_runner, 'runner');
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_venue, 'Order event', 'concert', now(), now() + interval '3 hours')
    returning id into v_event;
  insert into public.venue_suites (venue_id, name) values (v_venue, 'Suite 204')
    returning id into v_suite;
  insert into public.suite_event_assignments (venue_id, event_id, suite_id)
    values (v_venue, v_event, v_suite) returning id into v_assignment;

  -- A runner cannot write orders.
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.save_suite_order(v_assignment, '[]'::jsonb, null, '', 0);
    reset role;
    raise exception 'Runner created an order';
  exception when insufficient_privilege then
    reset role;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- Invalid items are rejected.
  begin
    perform public.save_suite_order(v_assignment, '[{"name": "Wings", "quantity": 1.5}]'::jsonb, null, '', 0);
    raise exception 'Fractional quantity accepted';
  exception when invalid_parameter_value then null;
  end;

  -- An empty draft cannot be confirmed.
  v_order := public.save_suite_order(v_assignment, '[]'::jsonb, null, '', 0);
  begin
    perform public.set_suite_order_status(v_order.id, 'confirmed', v_order.version);
    raise exception 'Empty order confirmed';
  exception when raise_exception then
    if sqlerrm not like 'Add at least one item%' then raise; end if;
  end;

  v_order := public.save_suite_order(
    v_assignment,
    '[{"name": " Charcuterie board ", "quantity": 2}]'::jsonb,
    now() + interval '1 hour', 'Gate 3', v_order.version);
  if v_order.version <> 2 or v_order.items -> 0 ->> 'name' <> 'Charcuterie board'
     or v_order.items -> 0 ->> 'notes' <> '' then
    raise exception 'Items were not normalized: %', v_order.items;
  end if;

  -- A stale version is a conflict.
  begin
    perform public.save_suite_order(v_assignment, '[]'::jsonb, null, '', 1);
    raise exception 'Stale save accepted';
  exception when serialization_failure then null;
  end;

  v_order := public.set_suite_order_status(v_order.id, 'confirmed', v_order.version);
  -- Editing a confirmed order returns it to draft.
  v_order := public.save_suite_order(v_assignment, v_order.items, v_order.deliver_at, 'Gate 4', v_order.version);
  if v_order.status <> 'draft' then
    raise exception 'Edited order stayed confirmed';
  end if;
  v_order := public.set_suite_order_status(v_order.id, 'confirmed', v_order.version);
  reset role;

  -- Suite staff mark it delivered; it is then final.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_order := public.set_suite_order_status(v_order.id, 'delivered', v_order.version);
  begin
    insert into public.suite_orders (venue_id, event_id, assignment_id)
      values (v_venue, v_event, v_assignment);
    raise exception 'Direct insert allowed';
  exception when insufficient_privilege then null;
  end;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.save_suite_order(v_assignment, '[]'::jsonb, null, '', v_order.version);
    raise exception 'Delivered order changed';
  exception when raise_exception then
    if sqlerrm not like 'A delivered order cannot be changed%' then raise; end if;
  end;
  reset role;

  raise notice 'Suite order checks passed';
end;
$$;

rollback;
