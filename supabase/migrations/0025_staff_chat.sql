-- Phase 3: staff chat. One-to-one and group conversations between active venue members.
--
-- Anyone who is an active member can chat, including administrators. Clients read chat
-- tables under row-level security, and every write goes through the functions below. Each
-- function checks that the caller is an active member, so a deactivated staff member loses
-- chat access on their next request. Realtime delivery follows the same rules.

-- ---- 1. Tables -----------------------------------------------------------------

create table chat_conversations (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  kind text not null check (kind in ('direct', 'group')),
  title text not null default '' check (length(title) <= 80),
  -- For direct chats: the two user ids in order, so a pair has exactly one conversation.
  direct_key text unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  check ((kind = 'direct') = (direct_key is not null))
);

create index chat_conversations_venue_idx on chat_conversations(venue_id, last_message_at);

create table chat_participants (
  conversation_id uuid not null references chat_conversations(id) on delete cascade,
  venue_id uuid not null references venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  last_delivered_at timestamptz,
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create index chat_participants_user_idx on chat_participants(user_id, venue_id);

create table chat_messages (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  conversation_id uuid not null references chat_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index chat_messages_conversation_idx on chat_messages(conversation_id, created_at);

-- ---- 2. Membership check and access ----------------------------------------------

-- True when the caller is a participant and still an active member of the venue.
create or replace function public.chat_is_member(p_conversation uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
      from chat_participants p
      join venue_memberships m
        on m.venue_id = p.venue_id and m.user_id = p.user_id
     where p.conversation_id = p_conversation
       and p.user_id = (select auth.uid())
       and m.status = 'active');
$$;

-- Name shown in chat: the staff profile name when there is one, then the account name.
create or replace function public.chat_person_name(p_user uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select nullif(btrim(s.full_name), '') from staff_profiles s where s.user_id = p_user limit 1),
    (select nullif(btrim(u.display_name), '') from user_profiles u where u.id = p_user),
    'Team member');
$$;

alter table chat_conversations enable row level security;
alter table chat_participants enable row level security;
alter table chat_messages enable row level security;

revoke all on chat_conversations, chat_participants, chat_messages from anon, authenticated;
grant select on chat_conversations, chat_participants, chat_messages to authenticated;

create policy chat_conversations_read on chat_conversations for select to authenticated
  using (public.chat_is_member(id));
create policy chat_participants_read on chat_participants for select to authenticated
  using (public.chat_is_member(conversation_id));
create policy chat_messages_read on chat_messages for select to authenticated
  using (public.chat_is_member(conversation_id));

-- ---- 3. Conversations ------------------------------------------------------------

create or replace function public.chat_open_direct(p_venue uuid, p_other uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := (select auth.uid());
  key text;
  conversation uuid;
begin
  if me is null or p_other is null or p_other = me then
    raise exception 'Choose someone else to message' using errcode = '22023';
  end if;
  if not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = me and status = 'active')
     or not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = p_other and status = 'active') then
    raise exception 'Both people must be active members of this venue' using errcode = '42501';
  end if;

  key := least(me::text, p_other::text) || '|' || greatest(me::text, p_other::text);
  insert into chat_conversations (venue_id, kind, direct_key, created_by)
  values (p_venue, 'direct', key, me)
  on conflict (direct_key) do nothing
  returning id into conversation;

  if conversation is null then
    select id into conversation from chat_conversations where direct_key = key;
    return conversation;
  end if;

  insert into chat_participants (conversation_id, venue_id, user_id)
  values (conversation, p_venue, me), (conversation, p_venue, p_other);
  return conversation;
end;
$$;

create or replace function public.chat_create_group(p_venue uuid, p_title text, p_members uuid[])
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := (select auth.uid());
  conversation uuid;
  member uuid;
  title text := btrim(coalesce(p_title, ''));
  chosen uuid[];
begin
  if not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = me and status = 'active') then
    raise exception 'Only active members can start a group' using errcode = '42501';
  end if;
  if length(title) not between 1 and 80 then
    raise exception 'Give the group a name (up to 80 characters)' using errcode = '22023';
  end if;

  chosen := array(select distinct m from unnest(coalesce(p_members, '{}'::uuid[])) m where m <> me);
  if cardinality(chosen) = 0 then
    raise exception 'Add at least one other person to the group' using errcode = '22023';
  end if;
  if cardinality(chosen) > 49 then
    raise exception 'A group can have up to 50 people' using errcode = '22023';
  end if;
  foreach member in array chosen loop
    if not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = member and status = 'active') then
      raise exception 'Every member must be an active member of this venue' using errcode = '42501';
    end if;
  end loop;

  insert into chat_conversations (venue_id, kind, title, created_by)
  values (p_venue, 'group', title, me)
  returning id into conversation;

  insert into chat_participants (conversation_id, venue_id, user_id, role)
  values (conversation, p_venue, me, 'admin');
  insert into chat_participants (conversation_id, venue_id, user_id)
  select conversation, p_venue, m from unnest(chosen) m;

  return conversation;
end;
$$;

-- Group admins add people. Added people see the whole history from the start.
create or replace function public.chat_add_members(p_conversation uuid, p_members uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := (select auth.uid());
  c chat_conversations%rowtype;
  member uuid;
  chosen uuid[];
begin
  select * into c from chat_conversations where id = p_conversation;
  if not found or c.kind <> 'group' then
    raise exception 'Only group chats can add people' using errcode = '22023';
  end if;
  if not exists (
    select 1 from chat_participants
     where conversation_id = p_conversation and user_id = me and role = 'admin') then
    raise exception 'Only a group admin can add people' using errcode = '42501';
  end if;

  chosen := array(select distinct m from unnest(coalesce(p_members, '{}'::uuid[])) m);
  foreach member in array chosen loop
    if not exists (select 1 from venue_memberships where venue_id = c.venue_id and user_id = member and status = 'active') then
      raise exception 'Every member must be an active member of this venue' using errcode = '42501';
    end if;
  end loop;
  if (select count(*) from chat_participants where conversation_id = p_conversation) + cardinality(chosen) > 50 then
    raise exception 'A group can have up to 50 people' using errcode = '22023';
  end if;

  insert into chat_participants (conversation_id, venue_id, user_id)
  select p_conversation, c.venue_id, m from unnest(chosen) m
  on conflict (conversation_id, user_id) do nothing;
end;
$$;

-- ---- 4. Messages and receipts ------------------------------------------------------

create or replace function public.chat_send(p_conversation uuid, p_body text)
returns chat_messages
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := (select auth.uid());
  c chat_conversations%rowtype;
  m chat_messages%rowtype;
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'You cannot send messages in this conversation' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_body, ''))) not between 1 and 2000 then
    raise exception 'Messages are 1 to 2000 characters' using errcode = '22023';
  end if;

  select * into c from chat_conversations where id = p_conversation;
  insert into chat_messages (venue_id, conversation_id, sender_id, body)
  values (c.venue_id, p_conversation, me, btrim(p_body))
  returning * into m;

  update chat_conversations set last_message_at = m.created_at where id = p_conversation;
  -- The sender has read their own message.
  update chat_participants
     set last_read_at = m.created_at, last_delivered_at = m.created_at
   where conversation_id = p_conversation and user_id = me;

  return m;
end;
$$;

-- Called when a client receives new messages, so others see "delivered".
create or replace function public.chat_mark_delivered(p_conversation uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  update chat_participants
     set last_delivered_at = now()
   where conversation_id = p_conversation and user_id = (select auth.uid());
end;
$$;

-- Called when someone opens the conversation. Reading also means it was delivered.
create or replace function public.chat_mark_read(p_conversation uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  update chat_participants
     set last_read_at = now(), last_delivered_at = now()
   where conversation_id = p_conversation and user_id = (select auth.uid());
end;
$$;

-- ---- 5. Conversation list ------------------------------------------------------------

create or replace function public.chat_list(p_venue uuid)
returns table (
  conversation_id uuid,
  kind text,
  title text,
  other_user_id uuid,
  member_count integer,
  last_message_at timestamptz,
  last_body text,
  last_sender_id uuid,
  last_sender_name text,
  unread_count integer
)
language sql stable security definer set search_path = public
as $$
  select c.id,
         c.kind,
         case when c.kind = 'direct' then public.chat_person_name(other.user_id) else c.title end,
         other.user_id,
         (select count(*)::integer from chat_participants x where x.conversation_id = c.id),
         c.last_message_at,
         latest.body,
         latest.sender_id,
         case when latest.sender_id is null then null
              else public.chat_person_name(latest.sender_id) end,
         (select count(*)::integer
            from chat_messages u
           where u.conversation_id = c.id
             and u.sender_id <> (select auth.uid())
             and u.created_at > coalesce(me.last_read_at, me.joined_at))
    from chat_conversations c
    join chat_participants me
      on me.conversation_id = c.id and me.user_id = (select auth.uid())
    left join lateral (
      select x.user_id
        from chat_participants x
       where x.conversation_id = c.id and x.user_id <> (select auth.uid())
       limit 1) other on c.kind = 'direct'
    left join lateral (
      select msg.body, msg.sender_id
        from chat_messages msg
       where msg.conversation_id = c.id
       order by msg.created_at desc
       limit 1) latest on true
   where c.venue_id = p_venue
     and public.chat_is_member(c.id)
   order by c.last_message_at desc nulls last, c.created_at desc;
$$;

-- ---- 6. Grants and realtime -----------------------------------------------------------

revoke execute on function public.chat_is_member(uuid) from public, anon;
revoke execute on function public.chat_person_name(uuid) from public, anon;
revoke execute on function public.chat_open_direct(uuid, uuid) from public, anon;
revoke execute on function public.chat_create_group(uuid, text, uuid[]) from public, anon;
revoke execute on function public.chat_add_members(uuid, uuid[]) from public, anon;
revoke execute on function public.chat_send(uuid, text) from public, anon;
revoke execute on function public.chat_mark_delivered(uuid) from public, anon;
revoke execute on function public.chat_mark_read(uuid) from public, anon;
revoke execute on function public.chat_list(uuid) from public, anon;

grant execute on function public.chat_is_member(uuid) to authenticated;
grant execute on function public.chat_person_name(uuid) to authenticated;
grant execute on function public.chat_open_direct(uuid, uuid) to authenticated;
grant execute on function public.chat_create_group(uuid, text, uuid[]) to authenticated;
grant execute on function public.chat_add_members(uuid, uuid[]) to authenticated;
grant execute on function public.chat_send(uuid, text) to authenticated;
grant execute on function public.chat_mark_delivered(uuid) to authenticated;
grant execute on function public.chat_mark_read(uuid) to authenticated;
grant execute on function public.chat_list(uuid) to authenticated;

-- Live updates: new messages and read receipts are pushed to members' open apps.
alter publication supabase_realtime add table public.chat_messages;
alter publication supabase_realtime add table public.chat_participants;
