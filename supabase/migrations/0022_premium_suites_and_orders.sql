-- Premium suite identities and per-suite food and beverage orders.
--
-- The venue operator supplied the labeled premium-level plan ("Suites Labeled.pdf")
-- on October 15, 2026. It identifies 29 suites, numbered 201 through 229, and
-- the operator confirmed that all 29 are available for service. Capacities,
-- locations and service zones were not supplied and are left blank.

-- ---- 1. Seed the 29 suites for the initial venue ---------------------------
-- Same venue identification as 0012 and 0021: the full name if exactly one
-- venue has it, otherwise a single 'CUTX' venue when no full-name venue exists.
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

  -- Replace the earlier seeded count of 26; keep any other operator value.
  update public.venues
     set service_suite_count = 29
   where id = v_venue
     and (service_suite_count is null or service_suite_count = 26);

  insert into public.venue_suites (venue_id, name)
  select v_venue, 'Suite ' || n
    from generate_series(201, 229) as n
  on conflict (venue_id, name) do nothing;
end;
$$;

-- ---- 2. Suite orders --------------------------------------------------------
-- One order per suite assignment (suite + event). Items are a JSON array of
-- {name, quantity, notes}. Writes go through the functions below only.
create table public.suite_orders (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  event_id uuid not null,
  assignment_id uuid not null unique,
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'delivered')),
  items jsonb not null default '[]'::jsonb
    check (jsonb_typeof(items) = 'array'),
  deliver_at timestamptz,
  notes text not null default '',
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (venue_id, event_id, assignment_id)
    references public.suite_event_assignments(venue_id, event_id, id)
    on delete cascade
);

create index suite_orders_venue_event_idx on public.suite_orders(venue_id, event_id);

alter table public.suite_orders enable row level security;
revoke insert, update, delete on public.suite_orders from anon, authenticated;
grant select on public.suite_orders to authenticated;

create policy suite_orders_read on public.suite_orders
  for select to authenticated
  using (public.is_venue_member(venue_id));

create trigger suite_orders_audit
after insert or update on public.suite_orders
for each row execute function public.audit_workflow_change();

-- Creates or replaces the order for an assignment. Editing a confirmed order
-- returns it to draft so the change is confirmed again. Delivered orders are final.
create or replace function public.save_suite_order(
  p_assignment uuid,
  p_items jsonb,
  p_deliver_at timestamptz,
  p_notes text,
  p_expected_version integer
)
returns public.suite_orders
language plpgsql security definer set search_path = public
as $$
declare
  a suite_event_assignments%rowtype;
  o suite_orders%rowtype;
  item jsonb;
  quantity numeric;
  clean jsonb := '[]'::jsonb;
begin
  select * into a from suite_event_assignments where id = p_assignment;
  if not found then
    raise exception 'Suite assignment not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(a.venue_id, 'manage_events') then
    raise exception 'Not authorized to change suite orders' using errcode = '42501';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'An order holds up to 100 items' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item) <> 'object'
       or jsonb_typeof(item -> 'name') is distinct from 'string'
       or jsonb_typeof(item -> 'quantity') is distinct from 'number'
       or (item ? 'notes' and jsonb_typeof(item -> 'notes') <> 'string') then
      raise exception 'Each item needs a name and a quantity' using errcode = '22023';
    end if;
    quantity := (item ->> 'quantity')::numeric;
    if length(btrim(item ->> 'name')) not between 1 and 200
       or quantity <> trunc(quantity) or quantity not between 1 and 999 then
      raise exception 'Each item needs a name and a whole-number quantity from 1 to 999'
        using errcode = '22023';
    end if;
    clean := clean || jsonb_build_array(jsonb_build_object(
      'name', btrim(item ->> 'name'),
      'quantity', quantity::integer,
      'notes', btrim(coalesce(item ->> 'notes', ''))
    ));
  end loop;

  select * into o from suite_orders where assignment_id = a.id for update;
  if not found then
    if coalesce(p_expected_version, 0) <> 0 then
      raise exception 'Conflict: this order was changed by someone else. Refresh and try again.'
        using errcode = '40001';
    end if;
    insert into suite_orders (venue_id, event_id, assignment_id, items, deliver_at, notes)
    values (a.venue_id, a.event_id, a.id, clean, p_deliver_at, btrim(coalesce(p_notes, '')))
    returning * into o;
    return o;
  end if;

  if o.version <> p_expected_version then
    raise exception 'Conflict: this order was changed by someone else. Refresh and try again.'
      using errcode = '40001';
  end if;
  if o.status = 'delivered' then
    raise exception 'A delivered order cannot be changed';
  end if;

  update suite_orders
     set items = clean,
         deliver_at = p_deliver_at,
         notes = btrim(coalesce(p_notes, '')),
         status = 'draft',
         version = version + 1,
         updated_at = now()
   where id = o.id
  returning * into o;
  return o;
end;
$$;

-- Draft -> confirmed (managers, needs at least one item) -> delivered (suite staff).
create or replace function public.set_suite_order_status(
  p_order uuid,
  p_to text,
  p_expected_version integer
)
returns public.suite_orders
language plpgsql security definer set search_path = public
as $$
declare
  o suite_orders%rowtype;
begin
  select * into o from suite_orders where id = p_order for update;
  if not found then
    raise exception 'Suite order not found' using errcode = 'P0002';
  end if;

  if o.status = 'draft' and p_to = 'confirmed' then
    if not public.has_permission(o.venue_id, 'manage_events') then
      raise exception 'Not authorized to confirm suite orders' using errcode = '42501';
    end if;
    if jsonb_array_length(o.items) = 0 then
      raise exception 'Add at least one item before confirming the order';
    end if;
  elsif o.status = 'confirmed' and p_to = 'delivered' then
    if not public.has_permission(o.venue_id, 'update_tasks') then
      raise exception 'Not authorized to mark suite orders delivered' using errcode = '42501';
    end if;
  else
    raise exception 'Suite orders move draft, confirmed, delivered (% to % is not allowed)',
      o.status, p_to;
  end if;

  if o.version <> p_expected_version then
    raise exception 'Conflict: this order was changed by someone else. Refresh and try again.'
      using errcode = '40001';
  end if;

  update suite_orders
     set status = p_to, version = version + 1, updated_at = now()
   where id = o.id
  returning * into o;
  return o;
end;
$$;

revoke execute on function public.save_suite_order(uuid, jsonb, timestamptz, text, integer)
  from public, anon;
revoke execute on function public.set_suite_order_status(uuid, text, integer)
  from public, anon;
grant execute on function public.save_suite_order(uuid, jsonb, timestamptz, text, integer)
  to authenticated;
grant execute on function public.set_suite_order_status(uuid, text, integer)
  to authenticated;
