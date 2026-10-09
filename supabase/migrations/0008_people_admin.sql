-- CUTX Premium Command: people and access administration.
-- Managers (manage_configuration) can list people, add a member by email, change roles and
-- departments, and suspend or restore access. Clients never read auth.users directly.

create or replace function public.list_venue_people(p_venue uuid)
returns table (
  user_id uuid,
  display_name text,
  email text,
  membership_status text,
  roles text[],
  departments text[]
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can view people' using errcode = '42501';
  end if;

  return query
  select m.user_id,
         coalesce(p.display_name, u.email, 'Team member'),
         u.email::text,
         m.status,
         coalesce((select array_agg(ra.role_code order by ra.role_code)
                     from role_assignments ra
                    where ra.venue_id = p_venue and ra.user_id = m.user_id), '{}'::text[]),
         coalesce((select array_agg(dm.department order by dm.department)
                     from department_memberships dm
                    where dm.venue_id = p_venue and dm.user_id = m.user_id), '{}'::text[])
    from venue_memberships m
    join auth.users u on u.id = m.user_id
    left join user_profiles p on p.id = m.user_id
   where m.venue_id = p_venue
   order by coalesce(p.display_name, u.email);
end;
$$;

-- Adds an existing account to the venue. The account must already exist in Supabase Auth.
create or replace function public.add_venue_member(p_venue uuid, p_email text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  found_id uuid;
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can add people' using errcode = '42501';
  end if;

  select id into found_id from auth.users where lower(email) = lower(trim(p_email));
  if found_id is null then
    raise exception 'No account exists for that email. Create the account in Supabase Auth first.';
  end if;

  insert into venue_memberships (venue_id, user_id, status)
  values (p_venue, found_id, 'active')
  on conflict (venue_id, user_id) do update set status = 'active';

  return found_id;
end;
$$;

create or replace function public.set_membership_status(p_venue uuid, p_user uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can change access' using errcode = '42501';
  end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'You cannot suspend your own access';
  end if;
  update venue_memberships set status = case when p_active then 'active' else 'suspended' end
   where venue_id = p_venue and user_id = p_user;
end;
$$;

create or replace function public.set_person_role(p_venue uuid, p_user uuid, p_role text, p_on boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can change roles' using errcode = '42501';
  end if;
  if not exists (select 1 from roles where code = p_role) then
    raise exception 'Unknown role %', p_role;
  end if;
  if not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = p_user) then
    raise exception 'That person is not a member of this venue';
  end if;
  -- Keep at least one director at the venue.
  if p_role = 'director' and not p_on and p_user = auth.uid() then
    if (select count(*) from role_assignments where venue_id = p_venue and role_code = 'director') <= 1 then
      raise exception 'The venue must keep at least one director';
    end if;
  end if;

  if p_on then
    insert into role_assignments (venue_id, user_id, role_code)
    values (p_venue, p_user, p_role)
    on conflict (venue_id, user_id, role_code) do nothing;
  else
    delete from role_assignments where venue_id = p_venue and user_id = p_user and role_code = p_role;
  end if;
end;
$$;

create or replace function public.set_person_department(p_venue uuid, p_user uuid, p_department text, p_on boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission(p_venue, 'manage_configuration') then
    raise exception 'Only administrators can change departments' using errcode = '42501';
  end if;
  if not exists (select 1 from venue_memberships where venue_id = p_venue and user_id = p_user) then
    raise exception 'That person is not a member of this venue';
  end if;

  if p_on then
    insert into department_memberships (venue_id, user_id, department)
    values (p_venue, p_user, p_department)
    on conflict do nothing;
  else
    delete from department_memberships where venue_id = p_venue and user_id = p_user and department = p_department;
  end if;
end;
$$;

-- Privileged helpers are callable only by signed-in users; the functions check permission themselves.
revoke execute on function public.list_venue_people(uuid) from public, anon;
revoke execute on function public.add_venue_member(uuid, text) from public, anon;
revoke execute on function public.set_membership_status(uuid, uuid, boolean) from public, anon;
revoke execute on function public.set_person_role(uuid, uuid, text, boolean) from public, anon;
revoke execute on function public.set_person_department(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.list_venue_people(uuid) to authenticated;
grant execute on function public.add_venue_member(uuid, text) to authenticated;
grant execute on function public.set_membership_status(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_person_role(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.set_person_department(uuid, uuid, text, boolean) to authenticated;
