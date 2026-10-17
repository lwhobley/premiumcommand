-- The venue's seating chart names the clubs: the one between suites 229 and 201 is the
-- West Club, the one between 215 and 216 is the Loge Club. Renames the placeholder clubs
-- from 0030 only; a club someone has already renamed keeps its name.
update public.venue_suites
   set name = 'West Club'
 where map_area = 'club_a' and name = 'Premium Club A'
   and not exists (
     select 1 from public.venue_suites other
      where other.venue_id = venue_suites.venue_id and other.name = 'West Club'
   );

update public.venue_suites
   set name = 'Loge Club'
 where map_area = 'club_b' and name = 'Premium Club B'
   and not exists (
     select 1 from public.venue_suites other
      where other.venue_id = venue_suites.venue_id and other.name = 'Loge Club'
   );
