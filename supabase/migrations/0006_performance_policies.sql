-- CUTX Premium Command: performance review fixes.
-- 1. Evaluate auth.uid() once per statement, not once per row.
-- 2. Split FOR ALL policies so each command has one permissive policy alongside any read policy.
-- 3. Index foreign keys used by the hot read paths.

-- ---- 1. auth.uid() as an initplan ------------------------------------------------

drop policy user_profiles_read_own on user_profiles;
create policy user_profiles_read_own on user_profiles for select to authenticated
  using (id = (select auth.uid()));

drop policy user_profiles_update_own on user_profiles;
create policy user_profiles_update_own on user_profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy briefing_ack_insert on briefing_acknowledgments;
create policy briefing_ack_insert on briefing_acknowledgments for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_venue_member(venue_id));

drop policy notifications_read on notifications;
create policy notifications_read on notifications for select to authenticated
  using (user_id = (select auth.uid()));

drop policy notifications_mark_read on notifications;
create policy notifications_mark_read on notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy announcements_insert on event_announcements;
create policy announcements_insert on event_announcements for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_events') and author_id = (select auth.uid()));

drop policy task_comments_insert on task_comments;
create policy task_comments_insert on task_comments for insert to authenticated
  with check (public.is_venue_member(venue_id) and author_id = (select auth.uid()));

drop policy event_staff_read on event_staff;
drop policy event_staff_write on event_staff;
create policy event_staff_read on event_staff for select to authenticated
  using (public.has_permission(venue_id, 'deploy_staff') or user_id = (select auth.uid()));
create policy event_staff_insert on event_staff for insert to authenticated
  with check (public.has_permission(venue_id, 'deploy_staff'));
create policy event_staff_update on event_staff for update to authenticated
  using (public.has_permission(venue_id, 'deploy_staff'))
  with check (public.has_permission(venue_id, 'deploy_staff'));
create policy event_staff_delete on event_staff for delete to authenticated
  using (public.has_permission(venue_id, 'deploy_staff'));

-- ---- 2. One permissive policy per command --------------------------------------

drop policy templates_write on checklist_templates;
create policy checklist_templates_insert on checklist_templates for insert to authenticated
  with check (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'));
create policy checklist_templates_update on checklist_templates for update to authenticated
  using (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'))
  with check (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'));
create policy checklist_templates_delete on checklist_templates for delete to authenticated
  using (venue_id is not null and public.has_permission(venue_id, 'manage_configuration'));

drop policy menu_write on event_menu_items;
create policy event_menu_items_insert on event_menu_items for insert to authenticated
  with check (public.has_permission(venue_id, 'view_culinary'));
create policy event_menu_items_update on event_menu_items for update to authenticated
  using (public.has_permission(venue_id, 'view_culinary'))
  with check (public.has_permission(venue_id, 'view_culinary'));
create policy event_menu_items_delete on event_menu_items for delete to authenticated
  using (public.has_permission(venue_id, 'view_culinary'));

drop policy venue_suites_write on venue_suites;
create policy venue_suites_insert on venue_suites for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_suites_update on venue_suites for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_suites_delete on venue_suites for delete to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'));

-- ---- 3. Indexes for hot foreign keys -------------------------------------------

create index if not exists event_tasks_template_id_idx on event_tasks(template_id);
create index if not exists event_staff_user_id_idx on event_staff(user_id);
create index if not exists event_staff_suite_idx on event_staff(suite_assignment_id);
create index if not exists service_requests_assigned_user_idx on service_requests(assigned_user_id);
create index if not exists suite_event_assignments_suite_idx on suite_event_assignments(suite_id);
create index if not exists inspection_instances_event_idx on inspection_instances(event_id);
create index if not exists inspection_instances_template_idx on inspection_instances(template_id);
create index if not exists notifications_event_idx on notifications(event_id);
create index if not exists beo_revisions_beo_idx on beo_revisions(beo_id);
create index if not exists culinary_batches_menu_idx on culinary_batches(menu_item_id);
