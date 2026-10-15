-- Trigger functions have no direct API use. Keep them callable only by their
-- triggers, not by anonymous or authenticated PostgREST clients.
revoke execute on function public.check_inspection_response_item()
  from public, anon, authenticated;
revoke execute on function public.check_inspection_template_venue()
  from public, anon, authenticated;
revoke execute on function public.create_user_profile()
  from public, anon, authenticated;
revoke execute on function public.guard_closeout_lifecycle()
  from public, anon, authenticated;

-- Split floor-plan writes so SELECT evaluates only the membership policy.
drop policy if exists venue_space_floor_plans_write
  on public.venue_space_floor_plans;
create policy venue_space_floor_plans_insert
  on public.venue_space_floor_plans for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_space_floor_plans_update
  on public.venue_space_floor_plans for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_space_floor_plans_delete
  on public.venue_space_floor_plans for delete to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'));
