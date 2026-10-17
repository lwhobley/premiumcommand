-- Premium sales packages: the offerings and current pricing shown on the Sales page.
--
-- Seeded from the premium seating pages of cutxeventcenter.com on October 16, 2026
-- (Premium Ticket Packages and The Premium Level Experience). Contact details from those pages
-- are deliberately left out. Every field, including prices, is editable by people with the new
-- manage_sales permission (directors and premium managers). Prices are stored as the text shown
-- to buyers, so they can be written exactly as sales wants them ("$18,000", "Included").
--
-- As published, the Half Season Silver suite total is $11,800, although $660 x 18 is $11,880.
-- It is seeded as published and can be corrected on the Sales page.

-- ---- 1. Permission --------------------------------------------------------------

insert into permissions (code, description)
values ('manage_sales', 'Edit premium sales packages and pricing')
on conflict (code) do nothing;

insert into role_permissions (role_code, permission_code)
values ('director', 'manage_sales'), ('premium_manager', 'manage_sales')
on conflict do nothing;

-- ---- 2. Table and access ----------------------------------------------------------

create table public.sales_packages (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  category text not null default '' check (length(category) <= 60),
  title text not null check (length(btrim(title)) between 1 and 120),
  summary text not null default '' check (length(summary) <= 2000),
  features text[] not null default '{}' check (cardinality(features) <= 30),
  -- [{"label": "Bronze · 10 seats", "price": "$18,000", "detail": "$500 per game · 36 games"}]
  price_rows jsonb not null default '[]'::jsonb
    check (jsonb_typeof(price_rows) = 'array' and jsonb_array_length(price_rows) <= 20),
  price_note text not null default '' check (length(price_note) <= 1000),
  image_url text check (image_url is null or image_url ~ '^https://'),
  sort_order integer not null default 0,
  active boolean not null default true,
  version integer not null default 1,
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index sales_packages_venue_idx on public.sales_packages(venue_id, sort_order);

alter table public.sales_packages enable row level security;
grant select, insert, update, delete on public.sales_packages to authenticated;

create policy sales_packages_read on public.sales_packages for select to authenticated
  using (public.is_venue_member(venue_id));
create policy sales_packages_insert on public.sales_packages for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_sales'));
create policy sales_packages_update on public.sales_packages for update to authenticated
  using (public.has_permission(venue_id, 'manage_sales'))
  with check (public.has_permission(venue_id, 'manage_sales'));
create policy sales_packages_delete on public.sales_packages for delete to authenticated
  using (public.has_permission(venue_id, 'manage_sales'));

-- Every change to an offering or a price is recorded, with the title it applied to.
create or replace function public.sales_packages_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  row_data sales_packages%rowtype;
begin
  row_data := case when tg_op = 'DELETE' then old else new end;
  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (row_data.venue_id, 'sales_package.' || lower(tg_op), 'sales_package', row_data.id,
          jsonb_build_object('title', row_data.title));
  return row_data;
end;
$$;

revoke execute on function public.sales_packages_audit() from public, anon, authenticated;

create trigger sales_packages_audit_trg
after insert or update or delete on public.sales_packages
for each row execute function public.sales_packages_audit();

-- ---- 3. Seed the published offerings -------------------------------------------------
-- Same venue identification as 0012, 0021, 0022, and 0030. Skipped if the venue already has
-- packages, so a rerun never duplicates or overwrites edits.

do $$
declare
  v_venue uuid;
  v_full_names constant text[] :=
    array['Credit Union of Texas Event Center', 'CUTX Event Center'];
  suite_amenities constant text[] := array[
    'Fully furnished suite with tables and chairs',
    'Wet bar',
    'In-suite catering service',
    'Suite attendant',
    'Exclusive access to the Premium Level and Lounge',
    'Free parking',
    'Flat-screen TV and free Wi-Fi'];
  suite_season_benefits constant text[] := array[
    'Option to buy your suite for Allen Americans playoff home games, concerts, and other events',
    'Affordable no-interest payment plans',
    'Personalized service from the Premium Level Client Team',
    'Pre-order food and beverages (minimum order required at ticket purchase)',
    'Exclusive access to the Premium Level Lounge and Bar'];
  club_benefits constant text[] := array[
    'Premium meal with The Premium Level Experience meal service',
    'Option to buy club seats (or comparable seats) for Allen Americans playoff home games, concerts, and other events',
    'Affordable no-interest payment plans',
    'Exclusive access to the Premium Level Lounge and Bar'];
  img constant text := 'https://www.cutxeventcenter.com/assets/img/';
begin
  if (select count(*) from public.venues where name = any (v_full_names)) = 1 then
    select id into v_venue from public.venues where name = any (v_full_names);
  elsif not exists (select 1 from public.venues where name = any (v_full_names))
        and (select count(*) from public.venues where name = 'CUTX') = 1 then
    select id into v_venue from public.venues where name = 'CUTX';
  else
    return;
  end if;

  if exists (select 1 from public.sales_packages where venue_id = v_venue) then
    return;
  end if;

  insert into public.sales_packages
    (venue_id, category, title, summary, features, price_rows, price_note, image_url, sort_order, updated_by)
  values
    (v_venue, 'Allen Americans Suites', 'Suite · Full Season',
     'Exclusive access to your private suite for all 36 Allen Americans regular season home games. Entertain in style, for business or pleasure.',
     suite_amenities || suite_season_benefits,
     '[{"label": "Bronze · 10 seats", "price": "$18,000", "detail": "$500 per game · 36 games"},
       {"label": "Silver · 12 seats", "price": "$21,600", "detail": "$600 per game · 36 games"},
       {"label": "Gold · 14 seats", "price": "$25,200", "detail": "$700 per game · 36 games"},
       {"label": "Platinum · 18 seats", "price": "$32,400", "detail": "$900 per game · 36 games"}]'::jsonb,
     'Additional suite tickets are $50 each. Food and beverage are not included in the suite ticket price.',
     img || 'Premium-Level-Suite-Hockey-Game-6424b04839.jpg', 10, null),

    (v_venue, 'Allen Americans Suites', 'Suite · Half Season',
     'Exclusive access to your private suite for 18 Allen Americans regular season home games.',
     suite_amenities || suite_season_benefits,
     '[{"label": "Bronze · 10 seats", "price": "$9,900", "detail": "$550 per game · 18 games"},
       {"label": "Silver · 12 seats", "price": "$11,800", "detail": "$660 per game · 18 games"},
       {"label": "Gold · 14 seats", "price": "$13,860", "detail": "$770 per game · 18 games"},
       {"label": "Platinum · 18 seats", "price": "$17,820", "detail": "$990 per game · 18 games"}]'::jsonb,
     'Additional suite tickets are $55 each. Food and beverage are not included in the suite ticket price.',
     img || 'Hockey-Fans-Cheering-from-Suite-dad05dafcb.jpg', 20, null),

    (v_venue, 'Allen Americans Suites', 'Suite · Partial Season',
     'Exclusive access to your private suite for 12 Allen Americans regular season home games.',
     suite_amenities || suite_season_benefits,
     '[{"label": "Bronze · 10 seats", "price": "$7,200", "detail": "$600 per game · 12 games"},
       {"label": "Silver · 12 seats", "price": "$8,640", "detail": "$720 per game · 12 games"},
       {"label": "Gold · 14 seats", "price": "$10,080", "detail": "$840 per game · 12 games"},
       {"label": "Platinum · 18 seats", "price": "$12,960", "detail": "$1,080 per game · 12 games"}]'::jsonb,
     'Additional suite tickets are $60 each. Food and beverage are not included in the suite ticket price.',
     img || 'Credit-Union-of-Texas-Event-Center-Suite-856c84b4ac.jpg', 30, null),

    (v_venue, 'Allen Americans Suites', 'Suite · Individual Games',
     'A luxury suite for a single Allen Americans hockey game.',
     suite_amenities || array[
       'Personalized service from the Premium Level Client Team',
       'Pre-order food and beverages (minimum order required at ticket purchase)',
       'Exclusive access to the Premium Level Lounge and Bar'],
     '[{"label": "10, 12, 14, or 18 person suites", "price": "$70 per seat", "detail": "From $700 per game"}]'::jsonb,
     'Food and beverage are not included in the suite ticket price.',
     img || 'Guests-laughing-in-suite-471a7b08a3.jpg', 40, null),

    (v_venue, 'Allen Americans Club Seats', 'Club Seats · Full Season',
     'Comfortable reserved leather seating with spectacular sight lines for all 36 Allen Americans home games, with The Premium Level Experience meal service.',
     club_benefits,
     '[{"label": "Full season · 36 games", "price": "$1,800", "detail": "$50 per game"}]'::jsonb,
     '', img || 'Club-Seat-cfb09db551.jpg', 50, null),

    (v_venue, 'Allen Americans Club Seats', 'Club Seats · Half Season',
     'Comfortable reserved leather seating for 18 Allen Americans home games, with The Premium Level Experience meal service.',
     club_benefits,
     '[{"label": "Half season · 18 games", "price": "$990", "detail": "$55 per game"}]'::jsonb,
     '', img || 'Americans-Rink-of-Red-2dff8e3e3b.jpg', 60, null),

    (v_venue, 'Allen Americans Club Seats', 'Club Seats · Partial Season',
     'Comfortable reserved leather seating for 12 Allen Americans home games, with The Premium Level Experience meal service.',
     club_benefits,
     '[{"label": "Partial season · 12 games", "price": "$720", "detail": "$60 per game"}]'::jsonb,
     '', img || 'Club-Seat-cfb09db551.jpg', 70, null),

    (v_venue, 'The Premium Level Experience', 'The Premium Level Experience',
     'A curated culinary experience at every Allen Americans home game, served by RS3 Strategic Hospitality, the exclusive Premium Level partner. Formerly Taste of Premium.',
     array[
       'Curated culinary service at every home game',
       'Consistent, high-quality food and service all season'],
     '[{"label": "Season Ticket Members with premium access", "price": "Included", "detail": "Complimentary meal each night"},
       {"label": "Other Premium Level guests", "price": "$20", "detail": "Per game"}]'::jsonb,
     '', img || 'Taste-of-Premium-Serving-47a9f1c9ee.jpg', 80, null);
end;
$$;
