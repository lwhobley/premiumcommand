-- Run after migration 0028. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_member uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_group uuid;
  v_device text := 'device:' || repeat('a', 64);
  v_address text := 'ip:' || repeat('b', 64);
  v_ok boolean;
  v_n integer;
  i integer;
begin
  -- ---- Sign-in attempts: 5 allowed, the 6th is refused and locks the key.
  for i in 1..5 loop
    v_ok := public.staff_login_take_attempt(v_device, 5, 15);
    if not v_ok then raise exception 'Attempt % was refused early', i; end if;
  end loop;
  if public.staff_login_take_attempt(v_device, 5, 15) then
    raise exception 'Sixth attempt was allowed';
  end if;
  if public.staff_login_take_attempt(v_device, 5, 15) then
    raise exception 'Locked device was allowed another attempt';
  end if;

  -- Clearing a device key (after a correct PIN) allows attempts again.
  perform public.staff_login_release(v_device, true);
  if not public.staff_login_take_attempt(v_device, 5, 15) then
    raise exception 'Cleared device is still locked';
  end if;

  -- A correct PIN gives one address attempt back instead of clearing the address.
  perform public.staff_login_take_attempt(v_address, 30, 15);
  perform public.staff_login_take_attempt(v_address, 30, 15);
  perform public.staff_login_release(v_address, false);
  select failures into v_n from public.staff_login_locks where lock_key = v_address;
  if v_n <> 1 then raise exception 'Address count was %, expected 1', v_n; end if;

  -- Apps cannot call the attempt functions directly.
  perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.staff_login_take_attempt(v_device, 5, 15);
    raise exception 'An app called the attempt function';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- ---- Chat setup.
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_admin, 'authenticated', 'authenticated', 'fix-admin@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_member, 'authenticated', 'authenticated', 'fix-member@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_outsider, 'authenticated', 'authenticated', 'fix-outsider@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Review fixes test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Fixes arena');
  insert into public.venue_memberships (venue_id, user_id) values (v_venue, v_admin), (v_venue, v_member);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_admin, 'runner'), (v_venue, v_member, 'runner');

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_group := public.chat_create_group(v_venue, 'Crew', array[v_member]);

  -- Names for every member in one call.
  select count(*) into v_n from public.chat_member_names(v_group);
  if v_n <> 2 then raise exception 'Expected 2 member names, got %', v_n; end if;

  -- Channel access: members of the venue only, and only well-formed chat topics.
  if not public.chat_channel_allowed('chat-presence-' || v_venue) then
    raise exception 'Member could not join the presence channel';
  end if;
  if not public.chat_channel_allowed('chat-changes-' || v_venue) then
    raise exception 'Member could not join the changes channel';
  end if;
  if public.chat_channel_allowed('chat-presence-not-a-venue') then
    raise exception 'Malformed topic was allowed';
  end if;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if public.chat_channel_allowed('chat-presence-' || v_venue) then
    raise exception 'Outsider could join the presence channel';
  end if;
  begin
    perform public.chat_member_names(v_group);
    raise exception 'Outsider read member names';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- A deactivated group admin can no longer add people.
  update public.venue_memberships set status = 'suspended' where venue_id = v_venue and user_id = v_admin;
  insert into public.venue_memberships (venue_id, user_id) values (v_venue, v_outsider);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.chat_add_members(v_group, array[v_outsider]);
    raise exception 'Deactivated admin added someone';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  raise notice 'Review fix checks passed';
end;
$$;

rollback;
