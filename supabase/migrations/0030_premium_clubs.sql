-- Premium clubs.
--
-- The venue operator identified the two open ends of the premium level, between
-- suites 229 and 201 and between suites 215 and 216, as premium clubs (October 16,
-- 2026). They are premium spaces like the suites: they can be added to an event,
-- move through the same setup states, take staff placements and orders, and are
-- shown and tappable on the premium-level map. Their names, capacities, and
-- service zones were not supplied; the seeded names are placeholders an
-- administrator can change.

-- Which outline on the premium-level map a space is drawn as, when it is not
-- matched by a suite number in its name. Values are defined in
-- lib/features/suites/domain/premium_level_layout.dart.
alter table public.venue_suites
  add column map_area text check (map_area ~ '^[a-z0-9_]{1,40}$'),
  add constraint venue_suites_venue_map_area_key unique (venue_id, map_area);

-- Same venue identification as 0012, 0021, and 0022: the full name if exactly
-- one venue has it, otherwise a single 'CUTX' venue when no full-name venue exists.
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

  -- A club already placed on the map, or a space already using the name, is left alone.
  insert into public.venue_suites (venue_id, name, map_area)
  select v_venue, c.name, c.map_area
    from (values ('Premium Club A', 'club_a'), ('Premium Club B', 'club_b')) as c(name, map_area)
   where not exists (
     select 1 from public.venue_suites s
      where s.venue_id = v_venue and (s.map_area = c.map_area or s.name = c.name)
   );
end;
$$;
