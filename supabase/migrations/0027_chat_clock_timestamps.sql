-- Chat timestamps use the wall clock at each call, not the start of the transaction.
--
-- now() returns the start time of the current transaction. A join, a message, and a read made
-- in one transaction would then share one timestamp, so "sent after you joined" and "read after
-- it was sent" would both be false. Each request is its own transaction in the app, so the
-- problem only showed up in the single-transaction SQL test. clock_timestamp() avoids it everywhere.

alter table chat_participants alter column joined_at set default clock_timestamp();
alter table chat_messages alter column created_at set default clock_timestamp();

create or replace function public.chat_mark_delivered(p_conversation uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  update chat_participants
     set last_delivered_at = clock_timestamp()
   where conversation_id = p_conversation and user_id = (select auth.uid());
end;
$$;

create or replace function public.chat_mark_read(p_conversation uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.chat_is_member(p_conversation) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  update chat_participants
     set last_read_at = clock_timestamp(), last_delivered_at = clock_timestamp()
   where conversation_id = p_conversation and user_id = (select auth.uid());
end;
$$;
