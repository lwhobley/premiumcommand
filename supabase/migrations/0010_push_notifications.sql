-- CUTX Premium Command: push notifications.
-- Devices register a token. Every new in-app notification is pushed to that person's devices
-- by the send-push Edge Function.

create extension if not exists pg_net with schema extensions;

create table device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on device_tokens(user_id);

alter table device_tokens enable row level security;
create policy device_tokens_own_read on device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on device_tokens from anon, authenticated;
grant select on device_tokens to authenticated;

-- A device belongs to whoever signed in last. Re-registering moves the token to the new user.
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  insert into device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language sql security definer set search_path = public
as $$
  delete from device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

-- Shared secret between the database and the Edge Function. Not readable by app roles.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
create table app_private.push_config (id int primary key default 1 check (id = 1), webhook_secret text not null);
revoke all on app_private.push_config from public, anon, authenticated;

create or replace function app_private.push_notification()
returns trigger
language plpgsql security definer set search_path = public, app_private, extensions
as $$
declare secret text;
begin
  select webhook_secret into secret from app_private.push_config where id = 1;
  if secret is null then
    return new;
  end if;
  perform net.http_post(
    url := 'https://tloxfuuzyadgkaejfhzx.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', secret),
    body := jsonb_build_object('notification_id', new.id)
  );
  return new;
exception when others then
  -- A push failure must never block the change that produced the notification.
  return new;
end;
$$;

create trigger notifications_push
after insert on notifications
for each row execute function app_private.push_notification();

-- The secret is generated in the database and read by the Edge Function through a
-- service-role-only function, so it never has to be copied anywhere.
insert into app_private.push_config(webhook_secret) values (encode(extensions.gen_random_bytes(24), 'hex')) on conflict (id) do nothing;

create or replace function public.push_webhook_secret()
returns text
language sql stable security definer set search_path = app_private
as $$ select webhook_secret from app_private.push_config where id = 1 $$;

revoke all on function public.push_webhook_secret() from public, anon, authenticated;
grant execute on function public.push_webhook_secret() to service_role;
