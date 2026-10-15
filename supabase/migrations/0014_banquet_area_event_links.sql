-- Explicitly associate banquet area profiles with events so an area can open
-- the event BEO even when the profile represents multiple physical rooms.
alter table public.events
  add constraint events_venue_id_id_key unique (venue_id, id);

alter table public.venue_banquet_areas
  add constraint venue_banquet_areas_venue_id_id_key unique (venue_id, id);

create table public.event_banquet_areas (
  venue_id uuid not null,
  event_id uuid not null,
  banquet_area_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (event_id, banquet_area_id),
  foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  foreign key (venue_id, banquet_area_id)
    references public.venue_banquet_areas(venue_id, id) on delete cascade
);

create index event_banquet_areas_venue_area_idx
  on public.event_banquet_areas(venue_id, banquet_area_id);

alter table public.event_banquet_areas enable row level security;
grant select, insert, delete on public.event_banquet_areas to authenticated;

create policy event_banquet_areas_read on public.event_banquet_areas
  for select to authenticated
  using (public.is_venue_member(venue_id));

create policy event_banquet_areas_insert on public.event_banquet_areas
  for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events'));

create policy event_banquet_areas_delete on public.event_banquet_areas
  for delete to authenticated
  using (public.has_permission(venue_id, 'manage_events'));
