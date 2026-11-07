-- Read-only event feed for the Storefront Workforce sync. The sync account is not a venue member,
-- so it cannot read any table directly. This function returns only the four fields the sync
-- needs, and only to that one account.

create or replace function public.storefront_sync_events()
returns table (
  event_id uuid,
  name text,
  event_type text,
  service_start timestamptz,
  service_end timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.name, e.event_type, e.service_start, e.service_end
    from public.events e
   where auth.uid() = 'e0665b38-0c30-4a3f-b463-1df8c3e7d714'::uuid
     and e.venue_id = '11eb9e38-03b3-4f40-a2ea-f5b1771e9416'::uuid
   order by e.service_start;
$$;

revoke all on function public.storefront_sync_events() from public, anon;
grant execute on function public.storefront_sync_events() to authenticated;
