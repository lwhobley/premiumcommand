-- Staff accounts with PIN-only sign-in.
--
-- Only an administrator (manage_configuration) creates, edits, deactivates, or removes
-- staff. A staff member signs in with a 4-digit PIN through the staff-login edge function.
-- Staff accounts have no password.
--
-- PINs are never stored. The edge functions compute a keyed fingerprint (HMAC-SHA256 over
-- the PIN, with a secret held only by the functions) and send only that fingerprint here.
-- The fingerprint is unique across all staff, so a PIN identifies one person by itself.
-- Failed sign-ins are counted per device and per network address, not per account,
-- because a PIN alone cannot be tied to an account before it matches.

-- ---- 1. Tables -------------------------------------------------------------

create table public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  employee_id text not null unique
    check (employee_id ~ '^[A-Z0-9-]{3,20}$'),
  full_name text not null check (length(btrim(full_name)) between 1 and 120),
  job_title text not null default '' check (length(job_title) <= 120),
  department text not null default 'operations'
    check (department in ('suites','banquets','culinary','beverage','lounge','operations')),
  contact_email text not null default '' check (length(contact_email) <= 254),
  contact_phone text not null default '' check (length(contact_phone) <= 40),
  emergency_contact_name text not null default '' check (length(emergency_contact_name) <= 120),
  emergency_contact_phone text not null default '' check (length(emergency_contact_phone) <= 40),
  start_date date,
  photo_path text,
  status text not null default 'active' check (status in ('active','inactive')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (venue_id, id)
);

create index staff_profiles_venue_idx on public.staff_profiles(venue_id);

create table public.staff_pins (
  profile_id uuid primary key references public.staff_profiles(id) on delete cascade,
  venue_id uuid not null references public.venues(id) on delete cascade,
  pin_fingerprint text not null unique check (pin_fingerprint ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);

-- Failed PIN sign-ins, counted per device ('device:') and per network address ('ip:').
-- Keys are SHA-256 hashes, not raw device or address values. Written only by staff-login.
create table public.staff_login_locks (
  lock_key text primary key check (lock_key ~ '^(device|ip):[0-9a-f]{64}$'),
  failures integer not null default 0 check (failures >= 0),
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

-- ---- 2. Access ---------------------------------------------------------------

alter table public.staff_profiles enable row level security;
alter table public.staff_pins enable row level security;
alter table public.staff_login_locks enable row level security;
revoke all on public.staff_login_locks from anon, authenticated;

-- Clients never touch PIN rows. Only the edge functions (service role) and the
-- security definer functions below reach them.
revoke all on public.staff_pins from anon, authenticated;

revoke all on public.staff_profiles from anon, authenticated;
grant select on public.staff_profiles to authenticated;

-- Staff see their own profile. Administrators see every profile at the venue.
create policy staff_profiles_read on public.staff_profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.has_permission(venue_id, 'manage_configuration')
  );

-- Admin check for the edge functions, which call this as the signed-in administrator.
create or replace function public.staff_can_manage(p_venue uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.has_permission(p_venue, 'manage_configuration');
$$;

-- ---- 3. Field validation -----------------------------------------------------

create or replace function public.staff_check_fields(p_fields jsonb)
returns void
language plpgsql immutable
as $$
declare
  allowed constant text[] := array[
    'employee_id','full_name','job_title','department','contact_email','contact_phone',
    'emergency_contact_name','emergency_contact_phone','start_date'];
  k text;
begin
  if jsonb_typeof(p_fields) is distinct from 'object' then
    raise exception 'Staff details must be an object' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(p_fields) loop
    if not (k = any (allowed)) then
      raise exception 'Unknown staff field %', k using errcode = '22023';
    end if;
  end loop;
  if upper(btrim(coalesce(p_fields->>'employee_id', ''))) !~ '^[A-Z0-9-]{3,20}$' then
    raise exception 'Employee ID must be 3 to 20 letters, digits, or hyphens' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_fields->>'full_name', ''))) not between 1 and 120 then
    raise exception 'Full name is required (up to 120 characters)' using errcode = '22023';
  end if;
  if coalesce(p_fields->>'department', 'operations') not in
     ('suites','banquets','culinary','beverage','lounge','operations') then
    raise exception 'Unknown department' using errcode = '22023';
  end if;
  if length(coalesce(p_fields->>'job_title', '')) > 120
     or length(coalesce(p_fields->>'contact_email', '')) > 254
     or length(coalesce(p_fields->>'contact_phone', '')) > 40
     or length(coalesce(p_fields->>'emergency_contact_name', '')) > 120
     or length(coalesce(p_fields->>'emergency_contact_phone', '')) > 40 then
    raise exception 'A staff detail is too long' using errcode = '22023';
  end if;
end;
$$;

-- ---- 4. Administrator actions ------------------------------------------------

create or replace function public.staff_create_profile(
  p_venue uuid,
  p_user uuid,
  p_fields jsonb,
  p_roles text[],
  p_pin_fingerprint text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_role text;
  v_employee text;
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can add staff' using errcode = '42501';
  end if;
  perform public.staff_check_fields(p_fields);
  if p_roles is null or cardinality(p_roles) = 0 then
    raise exception 'Assign at least one role so the staff member can use the app' using errcode = '22023';
  end if;
  -- Staff accounts get only the roles that do not unlock Administration, Closeout, or
  -- Banquets & Culinary. Managers assign anything else under People.
  if not (p_roles <@ array['suite_attendant', 'runner', 'beverage_lead']::text[]) then
    raise exception 'Staff accounts can be given only the suite attendant, runner, or beverage lead role'
      using errcode = '22023';
  end if;

  v_employee := upper(btrim(p_fields->>'employee_id'));

  insert into staff_profiles (
    venue_id, user_id, employee_id, full_name, job_title, department,
    contact_email, contact_phone, emergency_contact_name, emergency_contact_phone, start_date
  ) values (
    p_venue, p_user, v_employee, btrim(p_fields->>'full_name'),
    btrim(coalesce(p_fields->>'job_title', '')),
    coalesce(nullif(p_fields->>'department', ''), 'operations'),
    btrim(coalesce(p_fields->>'contact_email', '')),
    btrim(coalesce(p_fields->>'contact_phone', '')),
    btrim(coalesce(p_fields->>'emergency_contact_name', '')),
    btrim(coalesce(p_fields->>'emergency_contact_phone', '')),
    nullif(p_fields->>'start_date', '')::date
  )
  returning id into v_id;

  insert into staff_pins (profile_id, venue_id, pin_fingerprint)
  values (v_id, p_venue, p_pin_fingerprint);

  insert into venue_memberships (venue_id, user_id, status)
  values (p_venue, p_user, 'active')
  on conflict (venue_id, user_id) do update set status = 'active';

  foreach v_role in array p_roles loop
    if not exists (select 1 from roles where code = v_role) then
      raise exception 'Unknown role %', v_role using errcode = '22023';
    end if;
    insert into role_assignments (venue_id, user_id, role_code)
    values (p_venue, p_user, v_role)
    on conflict (venue_id, user_id, role_code) do nothing;
  end loop;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (p_venue, 'staff.created', 'staff_profile', v_id,
          jsonb_build_object('employee_id', v_employee, 'roles', p_roles));

  return v_id;
end;
$$;

create or replace function public.staff_update_profile(
  p_profile uuid,
  p_fields jsonb,
  p_expected_version integer
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s staff_profiles%rowtype;
begin
  select * into s from staff_profiles where id = p_profile for update;
  if not found then
    raise exception 'Staff profile not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(s.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can edit staff details' using errcode = '42501';
  end if;
  if s.version <> p_expected_version then
    raise exception 'Conflict: this profile was changed by someone else. Refresh and try again.'
      using errcode = '40001';
  end if;
  perform public.staff_check_fields(p_fields);

  update staff_profiles
     set employee_id = upper(btrim(p_fields->>'employee_id')),
         full_name = btrim(p_fields->>'full_name'),
         job_title = btrim(coalesce(p_fields->>'job_title', '')),
         department = coalesce(nullif(p_fields->>'department', ''), 'operations'),
         contact_email = btrim(coalesce(p_fields->>'contact_email', '')),
         contact_phone = btrim(coalesce(p_fields->>'contact_phone', '')),
         emergency_contact_name = btrim(coalesce(p_fields->>'emergency_contact_name', '')),
         emergency_contact_phone = btrim(coalesce(p_fields->>'emergency_contact_phone', '')),
         start_date = nullif(p_fields->>'start_date', '')::date,
         version = version + 1,
         updated_at = now()
   where id = p_profile;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (s.venue_id, 'staff.updated', 'staff_profile', p_profile,
          jsonb_build_object('fields', (select jsonb_agg(k) from jsonb_object_keys(p_fields) k)));
end;
$$;

-- The photo must sit at the path the app uploads to: <venue>/<profile>.jpg.
create or replace function public.staff_set_photo(p_profile uuid, p_path text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s staff_profiles%rowtype;
begin
  select * into s from staff_profiles where id = p_profile;
  if not found then
    raise exception 'Staff profile not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(s.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can change staff photos' using errcode = '42501';
  end if;
  if p_path is distinct from (s.venue_id::text || '/' || s.id::text || '.jpg') then
    raise exception 'Photo path does not match this staff member' using errcode = '22023';
  end if;
  update staff_profiles set photo_path = p_path, updated_at = now() where id = p_profile;
  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (s.venue_id, 'staff.photo_changed', 'staff_profile', p_profile, '{}'::jsonb);
end;
$$;

-- Receives the fingerprint computed by the staff-admin function. Device lockouts are not
-- cleared here; they expire on their own after 15 minutes.
create or replace function public.staff_set_pin(p_profile uuid, p_pin_fingerprint text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s staff_profiles%rowtype;
begin
  select * into s from staff_profiles where id = p_profile;
  if not found then
    raise exception 'Staff profile not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(s.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can set PINs' using errcode = '42501';
  end if;

  update staff_pins
     set pin_fingerprint = p_pin_fingerprint,
         updated_at = now()
   where profile_id = p_profile;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (s.venue_id, 'staff.pin_changed', 'staff_profile', p_profile, '{}'::jsonb);
end;
$$;

-- Deactivation blocks data access at once: row-level security checks membership status.
-- The staff-admin function also bans the account so it cannot refresh its session.
create or replace function public.staff_set_status(p_profile uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s staff_profiles%rowtype;
begin
  select * into s from staff_profiles where id = p_profile for update;
  if not found then
    raise exception 'Staff profile not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(s.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can change staff status' using errcode = '42501';
  end if;
  if s.user_id = auth.uid() and not p_active then
    raise exception 'You cannot deactivate your own account';
  end if;

  update staff_profiles
     set status = case when p_active then 'active' else 'inactive' end,
         version = version + 1,
         updated_at = now()
   where id = p_profile;

  update venue_memberships
     set status = case when p_active then 'active' else 'suspended' end
   where venue_id = s.venue_id and user_id = s.user_id;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (s.venue_id, case when p_active then 'staff.activated' else 'staff.deactivated' end,
          'staff_profile', p_profile, '{}'::jsonb);
end;
$$;

create or replace function public.staff_remove(p_profile uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s staff_profiles%rowtype;
begin
  select * into s from staff_profiles where id = p_profile for update;
  if not found then
    raise exception 'Staff profile not found' using errcode = 'P0002';
  end if;
  if not public.has_permission(s.venue_id, 'manage_configuration') then
    raise exception 'Only administrators can remove staff' using errcode = '42501';
  end if;
  if s.user_id = auth.uid() then
    raise exception 'You cannot remove your own account';
  end if;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (s.venue_id, 'staff.removed', 'staff_profile', p_profile,
          jsonb_build_object('employee_id', s.employee_id));

  delete from role_assignments where venue_id = s.venue_id and user_id = s.user_id;
  delete from department_memberships where venue_id = s.venue_id and user_id = s.user_id;
  delete from venue_memberships where venue_id = s.venue_id and user_id = s.user_id;
  delete from staff_profiles where id = p_profile;
end;
$$;

-- ---- 5. Function grants ------------------------------------------------------

revoke execute on function public.staff_can_manage(uuid) from public, anon;
revoke execute on function public.staff_check_fields(jsonb) from public, anon, authenticated;
revoke execute on function public.staff_create_profile(uuid, uuid, jsonb, text[], text) from public, anon;
revoke execute on function public.staff_update_profile(uuid, jsonb, integer) from public, anon;
revoke execute on function public.staff_set_photo(uuid, text) from public, anon;
revoke execute on function public.staff_set_pin(uuid, text) from public, anon;
revoke execute on function public.staff_set_status(uuid, boolean) from public, anon;
revoke execute on function public.staff_remove(uuid) from public, anon;

grant execute on function public.staff_can_manage(uuid) to authenticated;
grant execute on function public.staff_create_profile(uuid, uuid, jsonb, text[], text) to authenticated;
grant execute on function public.staff_update_profile(uuid, jsonb, integer) to authenticated;
grant execute on function public.staff_set_photo(uuid, text) to authenticated;
grant execute on function public.staff_set_pin(uuid, text) to authenticated;
grant execute on function public.staff_set_status(uuid, boolean) to authenticated;
grant execute on function public.staff_remove(uuid) to authenticated;

-- ---- 6. Photos ---------------------------------------------------------------
-- Private bucket. Administrators write photos. A staff member reads only their own photo.

insert into storage.buckets (id, name, public)
values ('staff-photos', 'staff-photos', false)
on conflict (id) do nothing;

create policy staff_photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'staff-photos'
    and (
      public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
      or exists (
        select 1 from public.staff_profiles s
         where s.user_id = (select auth.uid())
           and s.photo_path = name
      )
    )
  );

create policy staff_photos_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'staff-photos'
    and public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
  );

create policy staff_photos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'staff-photos'
    and public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
  )
  with check (
    bucket_id = 'staff-photos'
    and public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
  );
