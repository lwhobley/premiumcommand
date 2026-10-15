-- Run after migration 0026. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_group uuid;
  v_direct uuid;
  v_n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_a, 'authenticated', 'authenticated', 'push-a@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_b, 'authenticated', 'authenticated', 'push-b@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_c, 'authenticated', 'authenticated', 'push-c@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Chat push test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Push arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_a), (v_venue, v_b), (v_venue, v_c);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_a, 'runner'), (v_venue, v_b, 'runner'), (v_venue, v_c, 'runner');

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_group := public.chat_create_group(v_venue, 'Suite crew', array[v_b, v_c]);
  perform public.chat_send(v_group, 'Briefing at 6');
  v_direct := public.chat_open_direct(v_venue, v_b);
  perform public.chat_send(v_direct, 'Are you on shift?');
  reset role;

  -- The sender gets no alert. Each other member gets one per message, read at once, and tied to the chat.
  select count(*) into v_n from notifications where user_id = v_a and kind = 'chat';
  if v_n <> 0 then raise exception 'Sender was notified (%)', v_n; end if;
  select count(*) into v_n from notifications
   where user_id = v_b and kind = 'chat' and conversation_id = v_group and read_at is not null;
  if v_n <> 1 then raise exception 'Group member B was not notified once (%)', v_n; end if;
  select count(*) into v_n from notifications
   where user_id = v_c and kind = 'chat' and conversation_id = v_group;
  if v_n <> 1 then raise exception 'Group member C was not notified once (%)', v_n; end if;
  select count(*) into v_n from notifications
   where user_id = v_b and kind = 'chat' and conversation_id = v_direct;
  if v_n <> 1 then raise exception 'Direct recipient was not notified (%)', v_n; end if;

  -- A deactivated member is no longer notified.
  update venue_memberships set status = 'suspended' where venue_id = v_venue and user_id = v_c;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.chat_send(v_group, 'Doors open at 7');
  reset role;
  select count(*) into v_n from notifications where user_id = v_c and kind = 'chat' and conversation_id = v_group;
  if v_n <> 1 then raise exception 'Deactivated member was notified (%)', v_n; end if;

  -- Chat alerts stay out of unread counts.
  select count(*) into v_n from notifications where user_id = v_b and kind = 'chat' and read_at is null;
  if v_n <> 0 then raise exception 'Chat alerts counted as unread'; end if;

  raise notice 'Chat push checks passed';
end;
$$;

rollback;
