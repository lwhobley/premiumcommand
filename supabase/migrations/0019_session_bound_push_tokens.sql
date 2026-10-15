-- Push tokens belong to a live Auth session. A server-side sign-out removes
-- that session, so its token is excluded even if the client never called stop.
alter table public.device_tokens add column session_id uuid;
create index device_tokens_session_idx on public.device_tokens(session_id);

create or replace function public.register_device_token(p_token text, p_platform text)
returns void language plpgsql security definer set search_path = public, auth
as $$
declare current_session uuid := (auth.jwt() ->> 'session_id')::uuid;
begin
  if auth.uid() is null or current_session is null or not exists (
    select 1 from auth.sessions s where s.id = current_session and s.user_id = auth.uid()
  ) then
    raise exception 'An active session is required for push registration' using errcode = '42501';
  end if;
  if p_platform not in ('ios', 'android') or length(trim(p_token)) = 0 then
    raise exception 'Invalid push token' using errcode = '22023';
  end if;
  insert into public.device_tokens (token, user_id, platform, session_id)
  values (p_token, auth.uid(), p_platform, current_session)
  on conflict (token) do update set
    user_id = excluded.user_id, platform = excluded.platform,
    session_id = excluded.session_id, updated_at = now();
end;
$$;

create or replace function public.push_device_tokens(p_user uuid)
returns table(token text)
language sql stable security definer set search_path = public, auth
as $$
  select d.token from public.device_tokens d
  join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
  where d.user_id = p_user;
$$;
revoke execute on function public.push_device_tokens(uuid) from public, anon, authenticated;
grant execute on function public.push_device_tokens(uuid) to service_role;
