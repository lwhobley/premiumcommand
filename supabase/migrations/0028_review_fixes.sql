-- Fixes from the review of phases 1-3.
--
-- 1. PIN sign-in attempts are reserved atomically before the PIN is checked, so parallel requests
--    cannot exceed the limit. Each attempt takes a slot; a correct PIN gives the slot back.
-- 2. Adding people to a group requires the admin to still be an active member.
-- 3. One call returns every member's display name for a conversation.
-- 4. Chat Realtime channels are private: only active members of the venue can join them.

-- ---- 1. Sign-in attempts -------------------------------------------------------

-- Takes one attempt for a lock key. Returns false when the key is locked or this attempt goes
-- over the limit, in which case the key is locked for p_lock_minutes. Attempts older than the
-- window stop counting. Called only by the staff-login function (service role).
create or replace function public.staff_login_take_attempt(
  p_key text,
  p_max integer,
  p_lock_minutes integer
)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  stamp timestamptz := clock_timestamp();
  window_start timestamptz := clock_timestamp() - make_interval(mins => p_lock_minutes);
  attempts integer;
  locked timestamptz;
begin
  insert into staff_login_locks as l (lock_key, failures, locked_until, updated_at)
  values (p_key, 1, null, stamp)
  on conflict (lock_key) do update
    set failures = case
          when l.locked_until is not null and l.locked_until > stamp then l.failures
          when l.updated_at < window_start then 1
          else l.failures + 1
        end,
        locked_until = case
          when l.locked_until is not null and l.locked_until > stamp then l.locked_until
          else null
        end,
        updated_at = case
          when l.locked_until is not null and l.locked_until > stamp then l.updated_at
          else stamp
        end
  returning failures, locked_until into attempts, locked;

  if locked is not null and locked > stamp then
    return false;
  end if;

  if attempts > p_max then
    update staff_login_locks
       set failures = 0,
           locked_until = stamp + make_interval(mins => p_lock_minutes),
           updated_at = stamp
     where lock_key = p_key;
    return false;
  end if;
  return true;
end;
$$;

-- Gives back one attempt after a correct PIN. A device key is cleared; an address key drops by
-- one, so a venue's successful sign-ins never count toward its limit.
create or replace function public.staff_login_release(p_key text, p_clear boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_clear then
    delete from staff_login_locks where lock_key = p_key;
  else
    update staff_login_locks
       set failures = greatest(failures - 1, 0)
     where lock_key = p_key;
  end if;
end;
$$;

revoke execute on function public.staff_login_take_attempt(text, integer, integer)
  from public, anon, authenticated;
revoke execute on function public.staff_login_release(text, boolean)
  from public, anon, authenticated;
grant execute on function public.staff_login_take_attempt(text, integer, integer) to service_role;
grant execute on function public.staff_login_release(text, boolean) to service_role;

-- ---- 2. Group admins must still be active members ------------------------------

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
  if not public.chat_is_member(p_conversation) then
    raise exception 'You are no longer a member of this conversation' using errcode = '42501';
  end if;

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

-- ---- 3. Member names in one call ---------------------------------------------------

create or replace function public.chat_member_names(p_conversation uuid)
returns table (user_id uuid, name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  return query
  select p.user_id, public.chat_person_name(p.user_id)
    from chat_participants p
   where p.conversation_id = p_conversation;
end;
$$;

revoke execute on function public.chat_member_names(uuid) from public, anon;
grant execute on function public.chat_member_names(uuid) to authenticated;

-- ---- 4. Private chat channels -------------------------------------------------------
-- The app joins 'chat-changes-<venue>' and 'chat-presence-<venue>' as private channels.
-- Only active members of that venue may join, read presence, or publish their own presence.

create or replace function public.chat_channel_allowed(p_topic text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    public.is_venue_member(
      (substring(p_topic from '^chat-(?:changes|presence)-([0-9a-fA-F-]{36})$'))::uuid),
    false);
$$;

revoke execute on function public.chat_channel_allowed(text) from public, anon;
grant execute on function public.chat_channel_allowed(text) to authenticated;

create policy chat_channels_receive on realtime.messages
  for select to authenticated
  using (public.chat_channel_allowed(realtime.topic()));

create policy chat_presence_publish on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and public.chat_channel_allowed(realtime.topic()));
