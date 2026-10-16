-- The arena floor as a service area.
--
-- The venue operator identified the arena floor as a serviceable area on the
-- premium-level map (October 16, 2026). Like the suites and clubs it is a premium
-- space: it can be added to an event, move through the setup states, take staff
-- placements and orders, and is tappable on the map. It uses map_area
-- 'arena_floor' (migration 0030) and the floor outline already on the map.
--
-- It is named Main Arena Floor, the name the operator gave the same space as a
-- banquet area (migration 0013). The banquet area profile is unchanged.

-- Same venue identification as 0012, 0021, 0022, and 0030.
do $$
declare
  v_venue uuid;
  v_full_names constant text[] :=
    array['Credit Union of Texas Event Center', 'CUTX Event Center'];
begin
  if (select count(*) from public.venues where name = any (v_full_names)) = 1 then
    select id into v_venue from public.venues where name = any (v_full_names);
  elsif not exists (select 1 from public.venues where name = any (v_full_names))
        and (select count(*) from public.venues where name = 'CUTX') = 1 then
    select id into v_venue from public.venues where name = 'CUTX';
  else
    return;
  end if;

  insert into public.venue_suites (venue_id, name, map_area)
  select v_venue, 'Main Arena Floor', 'arena_floor'
   where not exists (
     select 1 from public.venue_suites s
      where s.venue_id = v_venue
        and (s.map_area = 'arena_floor' or s.name = 'Main Arena Floor')
   );
end;
$$;
