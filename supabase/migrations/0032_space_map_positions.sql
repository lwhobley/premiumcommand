-- Map positions for every premium space, so names and numbers can change.
--
-- Until now a suite was placed on the premium-level map by the plan number in its
-- name ('Suite 204' -> 204), so renaming or renumbering it moved it or took it off
-- the map. map_area (migration 0030) now also holds a plan suite number. Each suite
-- the map places today is pinned to that position here; after that an administrator
-- can rename or renumber any space without moving it.

-- The same rule the app used: the first group of digits in the name that is one of
-- the plan's suite numbers, 201 through 229. If two spaces at a venue match the same
-- number, or the number is already taken, only one (or none) is pinned and the rest
-- keep matching by name until an administrator places them.
with matches as (
  select s.id, s.venue_id, m.match[1] as num, m.ord
    from public.venue_suites s,
         lateral regexp_matches(s.name, '\d+', 'g') with ordinality as m(match, ord)
   where s.map_area is null
     and m.match[1] ~ '^2(0[1-9]|1[0-9]|2[0-9])$'
), first_match as (
  select distinct on (id) id, venue_id, num
    from matches
   order by id, ord
), chosen as (
  select distinct on (f.venue_id, f.num) f.id, f.num
    from first_match f
   where not exists (
     select 1 from public.venue_suites t
      where t.venue_id = f.venue_id and t.map_area = f.num
   )
   order by f.venue_id, f.num, f.id
)
update public.venue_suites s
   set map_area = c.num
  from chosen c
 where s.id = c.id;
