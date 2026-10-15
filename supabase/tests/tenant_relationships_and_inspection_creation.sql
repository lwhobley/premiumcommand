-- Run after migration 0015. Every test row is rolled back.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_first uuid := gen_random_uuid();
  v_second uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_event_first uuid;
  v_event_second uuid;
  v_template uuid;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'tenant-test@example.invalid',
      '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Tenant relationship test');
  insert into public.venues (id, organization_id, name) values
    (v_first, v_org, 'First test venue'), (v_second, v_org, 'Second test venue');
  insert into public.venue_memberships (venue_id, user_id) values (v_first, v_director);
  insert into public.role_assignments (venue_id, user_id, role_code)
    values (v_first, v_director, 'director');
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_first, 'First event', 'concert', now(), now() + interval '3 hours')
    returning id into v_event_first;
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_second, 'Second event', 'concert', now(), now() + interval '3 hours')
    returning id into v_event_second;
  select id into v_template from public.checklist_templates where venue_id is null limit 1;
  if v_template is null then raise exception 'No shared checklist template exists'; end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;

  begin
    insert into public.event_tasks (venue_id, event_id, department, title)
      values (v_first, v_event_second, 'operations', 'Invalid task');
    raise exception 'Cross-venue task accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.event_staff (venue_id, event_id, display_name)
      values (v_first, v_event_second, 'Invalid staff');
    raise exception 'Cross-venue staff accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.event_announcements (venue_id, event_id, body)
      values (v_first, v_event_second, 'Invalid announcement');
    raise exception 'Cross-venue announcement accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.inspection_instances (venue_id, event_id, template_id)
      values (v_first, v_event_second, v_template);
    raise exception 'Cross-venue inspection accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.inspection_instances
      (venue_id, event_id, template_id, status, approved_by, approved_at)
    values (v_first, v_event_first, v_template, 'approved', v_director, now());
    raise exception 'Preapproved inspection accepted';
  exception when insufficient_privilege then
    if sqlerrm not like '%row-level security policy%inspection_instances%' then raise; end if;
  end;

  insert into public.inspection_instances (venue_id, event_id, template_id)
    values (v_first, v_event_first, v_template);
  reset role;
  raise notice 'Tenant relationship and inspection creation checks passed';
end;
$$;

rollback;
