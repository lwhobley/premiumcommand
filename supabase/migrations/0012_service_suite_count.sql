-- Venue-level service capacity. This is a count, not a list of suite identities.
-- Individual suite records are added only when their real identifiers are known.
alter table public.venues
  add column service_suite_count integer
  check (service_suite_count is null or service_suite_count >= 0);

-- Record the confirmed count for the initial venue if it has been provisioned.
-- Do not create a venue or infer any suite names from the count.
update public.venues
   set service_suite_count = 26
 where name in ('Credit Union of Texas Event Center', 'CUTX Event Center')
   and (select count(*) from public.venues
         where name in ('Credit Union of Texas Event Center', 'CUTX Event Center')) = 1;

create or replace function public.set_service_suite_count(
  p_venue uuid,
  p_count integer
)
returns integer
language plpgsql security definer set search_path = public
as $$
begin
  if p_count is null or p_count < 0 then
    raise exception 'Suite count must be zero or greater' using errcode = '22023';
  end if;
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Not authorized to configure this venue' using errcode = '42501';
  end if;

  update public.venues
     set service_suite_count = p_count
   where id = p_venue;
  if not found then
    raise exception 'Venue not found' using errcode = 'P0002';
  end if;
  return p_count;
end;
$$;

revoke execute on function public.set_service_suite_count(uuid, integer)
  from public, anon;
grant execute on function public.set_service_suite_count(uuid, integer)
  to authenticated;
