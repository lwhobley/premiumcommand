-- Each database must be configured with its own Edge Function endpoint.
-- No endpoint is seeded, so staging and local databases cannot send to production.
alter table app_private.push_config
  add column endpoint_url text check (
    endpoint_url is null or endpoint_url ~ '^https://[^/]+/functions/v1/send-push$'
  );

create or replace function app_private.push_notification()
returns trigger
language plpgsql security definer set search_path = public, app_private, extensions
as $$
declare
  push_secret text;
  push_url text;
begin
  select webhook_secret, endpoint_url into push_secret, push_url
    from app_private.push_config where id = 1;
  if push_url is null or push_secret is null then
    return new;
  end if;
  perform net.http_post(
    url := push_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', push_secret
    ),
    body := jsonb_build_object('notification_id', new.id)
  );
  return new;
exception when others then
  -- Keep the business write, but put enqueue failures in database logs.
  raise warning 'Push enqueue failed for notification %: %', new.id, sqlerrm;
  return new;
end;
$$;
