-- Phase 3b: push alerts for chat messages.
--
-- Each new message creates one notification per active member of the conversation, other than
-- the sender. The existing push path (notifications -> send-push) delivers it to that person's
-- devices. Only current members are notified: a removed or deactivated person is no longer a
-- participant or an active member, so they receive nothing.
--
-- The alert text is generic ("New message"), so message content does not appear on a lock screen.
-- Chat rows are created already read, so they never add to an unread count, and the Communications
-- inbox hides them, leaving chat in its own list.

alter table notifications
  add column conversation_id uuid references chat_conversations(id) on delete cascade;

create index notifications_conversation_idx on notifications(conversation_id);

create or replace function public.chat_message_notify()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  conv chat_conversations%rowtype;
  sender_name text;
begin
  select * into conv from chat_conversations where id = new.conversation_id;
  sender_name := public.chat_person_name(new.sender_id);

  insert into notifications (venue_id, user_id, kind, title, body, conversation_id, read_at)
  select new.venue_id,
         p.user_id,
         'chat',
         case when conv.kind = 'group' then conv.title else sender_name end,
         case when conv.kind = 'group' then sender_name || ': New message' else 'New message' end,
         new.conversation_id,
         now()
    from chat_participants p
    join venue_memberships m
      on m.venue_id = p.venue_id and m.user_id = p.user_id
   where p.conversation_id = new.conversation_id
     and p.user_id <> new.sender_id
     and m.status = 'active';

  return new;
end;
$$;

revoke execute on function public.chat_message_notify() from public, anon, authenticated;

create trigger chat_messages_notify
after insert on chat_messages
for each row execute function public.chat_message_notify();
