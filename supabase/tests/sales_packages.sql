-- Run after migration 0034. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_package uuid;
  v_n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_manager, 'authenticated', 'authenticated', 'sales-manager@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'sales-runner@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Sales test');
  insert into public.venues (id, organization_id, name) values (v_venue, v_org, 'Sales arena');
  insert into public.venue_memberships (venue_id, user_id) values (v_venue, v_manager), (v_venue, v_runner);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_manager, 'premium_manager'), (v_venue, v_runner, 'runner');

  -- A premium manager adds and reprices a package.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.sales_packages (venue_id, category, title, price_rows)
  values (v_venue, 'Club Seats', 'Club Seats · Full Season',
          '[{"label": "Full season · 36 games", "price": "$1,800", "detail": "$50 per game"}]')
  returning id into v_package;
  update public.sales_packages
     set price_rows = '[{"label": "Full season · 36 games", "price": "$1,900", "detail": "$52.78 per game"}]',
         version = version + 1
   where id = v_package;
  reset role;

  if (select price_rows -> 0 ->> 'price' from public.sales_packages where id = v_package) <> '$1,900' then
    raise exception 'Price change was not saved';
  end if;
  select count(*) into v_n from public.audit_logs
   where entity = 'sales_package' and entity_id = v_package;
  if v_n <> 2 then raise exception 'Expected 2 audit entries, found %', v_n; end if;

  -- A runner can read packages but not change them.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.sales_packages where venue_id = v_venue;
  if v_n <> 1 then raise exception 'Runner could not read packages'; end if;

  update public.sales_packages set title = 'Changed' where id = v_package;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'Runner changed a package'; end if;

  begin
    insert into public.sales_packages (venue_id, title) values (v_venue, 'Runner package');
    raise exception 'Runner added a package';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- Image links must be https.
  begin
    insert into public.sales_packages (venue_id, title, image_url) values (v_venue, 'Bad image', 'http://example.com/a.jpg');
    raise exception 'Non-https image accepted';
  exception when check_violation then
    null;
  end;

  raise notice 'Sales package checks passed';
end;
$$;

rollback;
