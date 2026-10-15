-- Floor Plan Studio: measured room dimensions and a generated round-table layout per
-- venue space, so Premium Spaces and the Event Workspace can show a 3D preview.
-- Config-like data, following the venue_suites pattern: no state machine, plain
-- read/write RLS gated by manage_configuration.

-- A floor plan must belong to the same venue as its physical space.
alter table public.venue_spaces
  add constraint venue_spaces_venue_id_id_key unique (venue_id, id);

create table if not exists venue_space_floor_plans (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venues(id) on delete cascade,
  venue_space_id uuid not null,
  width_feet numeric not null check (width_feet > 0),
  depth_feet numeric not null check (depth_feet > 0),
  verified boolean not null default false,
  table_diameter_feet numeric not null default 6 check (table_diameter_feet > 0),
  seats_per_table integer not null default 10 check (seats_per_table > 0),
  layout jsonb not null default '[]'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (venue_space_id),
  foreign key (venue_id, venue_space_id)
    references public.venue_spaces(venue_id, id) on delete cascade
);

-- Early Floor Plan Studio prototypes created this table with only a
-- venue_space_id foreign key. Tighten those installations as well.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.venue_space_floor_plans'::regclass
       and conname = 'venue_space_floor_plans_venue_id_venue_space_id_fkey'
  ) then
    alter table public.venue_space_floor_plans
      add constraint venue_space_floor_plans_venue_id_venue_space_id_fkey
      foreign key (venue_id, venue_space_id)
      references public.venue_spaces(venue_id, id) on delete cascade;
  end if;
end;
$$;

alter table venue_space_floor_plans enable row level security;
grant select, insert, update, delete on public.venue_space_floor_plans to authenticated;

drop policy if exists venue_space_floor_plans_read on venue_space_floor_plans;
create policy venue_space_floor_plans_read on venue_space_floor_plans for select to authenticated
  using (public.is_venue_member(venue_id));

drop policy if exists venue_space_floor_plans_write on venue_space_floor_plans;
create policy venue_space_floor_plans_write on venue_space_floor_plans for all to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));
