-- Run after migration 0025. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_direct uuid;
  v_again uuid;
  v_group uuid;
  v_msg chat_messages;
  v_n integer;
  v_unread integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_a, 'authenticated', 'authenticated', 'chat-a@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_b, 'authenticated', 'authenticated', 'chat-b@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_c, 'authenticated', 'authenticated', 'chat-c@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_outsider, 'authenticated', 'authenticated', 'chat-x@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Chat test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Chat arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_a), (v_venue, v_b), (v_venue, v_c);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_a, 'runner'), (v_venue, v_b, 'runner'), (v_venue, v_c, 'runner');

  -- A opens a direct chat with B. Opening it again returns the same conversation.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_direct := public.chat_open_direct(v_venue, v_b);
  v_again := public.chat_open_direct(v_venue, v_b);
  if v_direct <> v_again then raise exception 'Direct chat was duplicated'; end if;

  v_msg := public.chat_send(v_direct, '  Gate 3 is open  ');
  if v_msg.body <> 'Gate 3 is open' then raise exception 'Message was not trimmed'; end if;
  reset role;

  -- B sees one unread message in the list.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select unread_count into v_unread from public.chat_list(v_venue) where conversation_id = v_direct;
  if v_unread <> 1 then raise exception 'Unread count was %, expected 1', v_unread; end if;
  perform public.chat_mark_read(v_direct);
  select unread_count into v_unread from public.chat_list(v_venue) where conversation_id = v_direct;
  if v_unread <> 0 then raise exception 'Unread count did not clear after reading'; end if;
  reset role;

  -- A sees that B has read the message (last_read_at after the message).
  select count(*) into v_n from public.chat_participants p
   where p.conversation_id = v_direct and p.user_id = v_b and p.last_read_at >= v_msg.created_at;
  if v_n <> 1 then raise exception 'Read receipt was not recorded'; end if;

  -- A group with A, B, and C. A is the group admin.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_group := public.chat_create_group(v_venue, 'Suite crew', array[v_b, v_c]);
  perform public.chat_send(v_group, 'Briefing at 6');
  reset role;

  -- An outsider cannot read, send, or open chats here.
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.chat_messages;
  if v_n <> 0 then raise exception 'Outsider can read messages'; end if;
  begin
    perform public.chat_send(v_group, 'hello');
    raise exception 'Outsider sent a message';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- Only a group admin can add people. B is a plain member, so B cannot add anyone.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.chat_add_members(v_group, array[v_outsider]);
    raise exception 'Plain member added someone';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- Deactivating C ends C's access to the chat, including history.
  update public.venue_memberships set status = 'suspended' where venue_id = v_venue and user_id = v_c;
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.chat_messages where conversation_id = v_group;
  if v_n <> 0 then raise exception 'Deactivated member still reads history'; end if;
  reset role;

  raise notice 'Staff chat checks passed';
end;
$$;

rollback;
