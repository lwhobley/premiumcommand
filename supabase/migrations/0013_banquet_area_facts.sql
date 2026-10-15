-- Confirmed CUTX banquet area facts. A meeting-room group is not a single
-- physical room, so it has no venue_space_id until the two rooms are named.
create table public.venue_banquet_areas (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  venue_space_id uuid,
  name text not null check (length(trim(name)) > 0),
  kind text not null,
  space_count integer not null default 1 check (space_count > 0),
  capacity_per_space integer check (capacity_per_space is null or capacity_per_space > 0),
  area_square_feet integer check (area_square_feet is null or area_square_feet > 0),
  can_combine boolean not null default false,
  combined_capacity integer check (combined_capacity is null or combined_capacity > 0),
  has_full_service_bar boolean,
  created_at timestamptz not null default now(),
  unique (venue_id, name),
  check (combined_capacity is null or can_combine),
  foreign key (venue_id, venue_space_id)
    references public.venue_spaces(venue_id, id)
);
create index venue_banquet_areas_venue_idx on public.venue_banquet_areas(venue_id);
create index venue_banquet_areas_space_idx on public.venue_banquet_areas(venue_id, venue_space_id)
  where venue_space_id is not null;

alter table public.venue_banquet_areas enable row level security;
grant select, insert, update, delete on public.venue_banquet_areas to authenticated;
create policy banquet_areas_read on public.venue_banquet_areas
  for select to authenticated using (public.is_venue_member(venue_id));
create policy banquet_areas_insert on public.venue_banquet_areas
  for insert to authenticated with check (public.has_permission(venue_id, 'manage_configuration'));
create policy banquet_areas_update on public.venue_banquet_areas
  for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy banquet_areas_delete on public.venue_banquet_areas
  for delete to authenticated using (public.has_permission(venue_id, 'manage_configuration'));

-- Seed only if the initial venue can be identified unambiguously. These two
-- names were provided by the venue operator and represent physical spaces.
with target as (
  select id from public.venues
   where name in ('Credit Union of Texas Event Center', 'CUTX Event Center', 'CUTX')
     and (select count(*) from public.venues
           where name in ('Credit Union of Texas Event Center', 'CUTX Event Center', 'CUTX')) = 1
), names(name, space_type) as (
  values ('Main Arena Floor', 'arena_floor'),
         ('Premium Level Lounge', 'premium_lounge')
)
insert into public.venue_spaces (venue_id, name, space_type)
select target.id, names.name, names.space_type
  from target cross join names
 where not exists (
   select 1 from public.venue_spaces existing
    where existing.venue_id = target.id and existing.name = names.name
 );

with target as (
  select id from public.venues
   where name in ('Credit Union of Texas Event Center', 'CUTX Event Center', 'CUTX')
     and (select count(*) from public.venues
           where name in ('Credit Union of Texas Event Center', 'CUTX Event Center', 'CUTX')) = 1
), facts(name, kind, space_count, capacity_per_space, area_square_feet, can_combine, has_full_service_bar) as (
  values
    ('Main Arena Floor', 'arena_floor', 1, 900, 17000, false, null::boolean),
    ('Premium Level Lounge', 'premium_lounge', 1, 100, 2000, false, true),
    ('Meeting Rooms', 'meeting_room_group', 2, 32, null::integer, true, null::boolean)
)
insert into public.venue_banquet_areas (
  venue_id, venue_space_id, name, kind, space_count, capacity_per_space,
  area_square_feet, can_combine, combined_capacity, has_full_service_bar
)
select target.id,
       case when facts.kind = 'meeting_room_group' then null
            else (select s.id from public.venue_spaces s
                   where s.venue_id = target.id and s.name = facts.name
                     and (select count(*) from public.venue_spaces matches
                           where matches.venue_id = target.id
                             and matches.name = facts.name) = 1) end,
       facts.name, facts.kind, facts.space_count, facts.capacity_per_space,
       facts.area_square_feet, facts.can_combine, null, facts.has_full_service_bar
  from target cross join facts
on conflict (venue_id, name) do update set
  venue_space_id = excluded.venue_space_id,
  kind = excluded.kind,
  space_count = excluded.space_count,
  capacity_per_space = excluded.capacity_per_space,
  area_square_feet = excluded.area_square_feet,
  can_combine = excluded.can_combine,
  has_full_service_bar = excluded.has_full_service_bar;
