-- Run after migration 0011. All rows are rolled back.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_first uuid := gen_random_uuid();
  v_second uuid := gen_random_uuid();
  v_space uuid := gen_random_uuid();
begin
  insert into public.organizations (id, name) values (v_org, 'Floor plan tenant test');
  insert into public.venues (id, organization_id, name) values
    (v_first, v_org, 'First floor plan venue'),
    (v_second, v_org, 'Second floor plan venue');
  insert into public.venue_spaces (id, venue_id, name, space_type)
    values (v_space, v_second, 'Second venue room', 'banquet');

  begin
    insert into public.venue_space_floor_plans
      (venue_id, venue_space_id, width_feet, depth_feet)
    values (v_first, v_space, 40, 30);
    raise exception 'Floor plan was linked to a space in another venue';
  exception when foreign_key_violation then
    null;
  end;

  insert into public.venue_space_floor_plans
    (venue_id, venue_space_id, width_feet, depth_feet)
  values (v_second, v_space, 40, 30);

  raise notice 'Floor plan venue boundary checks passed';
end;
$$;

rollback;
