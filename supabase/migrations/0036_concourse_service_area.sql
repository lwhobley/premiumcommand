-- The concourse as a service area.
--
-- The venue operator identified the concourse, which wraps around the whole lower
-- level beneath the bowl, as a serviceable area on the map (October 17, 2026). Like
-- the arena floor it is a premium space: it can be added to an event, move through
-- the setup states, take staff placements and orders, and is tappable on the map. It
-- uses map_area 'concourse', drawn at ground level under the premium level.

-- Same venue identification as 0012, 0021, 0022, 0030, and 0031.
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
  select v_venue, 'Concourse', 'concourse'
   where not exists (
     select 1 from public.venue_suites s
      where s.venue_id = v_venue
        and (s.map_area = 'concourse' or s.name = 'Concourse')
   );
end;
$$;
