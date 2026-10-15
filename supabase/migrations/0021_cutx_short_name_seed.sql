-- Some installations provisioned the initial venue as 'CUTX', which 0012 and
-- 0013 do not match. Seed the same confirmed facts for that venue only when no
-- full-name venue exists and exactly one 'CUTX' venue does. Values an operator
-- has already set are kept.
do $$
declare
  v_venue uuid;
begin
  if exists (select 1 from public.venues
              where name in ('Credit Union of Texas Event Center', 'CUTX Event Center'))
     or (select count(*) from public.venues where name = 'CUTX') <> 1 then
    return;
  end if;
  select id into v_venue from public.venues where name = 'CUTX';

  update public.venues
     set service_suite_count = 26
   where id = v_venue and service_suite_count is null;

  insert into public.venue_spaces (venue_id, name, space_type)
  select v_venue, names.name, names.space_type
    from (values ('Main Arena Floor', 'arena_floor'),
                 ('Premium Level Lounge', 'premium_lounge')) as names(name, space_type)
   where not exists (
     select 1 from public.venue_spaces existing
      where existing.venue_id = v_venue and existing.name = names.name
   );

  insert into public.venue_banquet_areas (
    venue_id, venue_space_id, name, kind, space_count, capacity_per_space,
    area_square_feet, can_combine, combined_capacity, has_full_service_bar
  )
  select v_venue,
         case when facts.kind = 'meeting_room_group' then null
              else (select s.id from public.venue_spaces s
                     where s.venue_id = v_venue and s.name = facts.name
                       and (select count(*) from public.venue_spaces matches
                             where matches.venue_id = v_venue
                               and matches.name = facts.name) = 1) end,
         facts.name, facts.kind, facts.space_count, facts.capacity_per_space,
         facts.area_square_feet, facts.can_combine, null, facts.has_full_service_bar
    from (values
      ('Main Arena Floor', 'arena_floor', 1, 900, 17000, false, null::boolean),
      ('Premium Level Lounge', 'premium_lounge', 1, 100, 2000, false, true),
      ('Meeting Rooms', 'meeting_room_group', 2, 32, null::integer, true, null::boolean)
    ) as facts(name, kind, space_count, capacity_per_space, area_square_feet,
               can_combine, has_full_service_bar)
  on conflict (venue_id, name) do nothing;
end;
$$;
