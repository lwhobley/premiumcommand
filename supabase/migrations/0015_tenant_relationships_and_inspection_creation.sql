-- Enforce tenant and event identity across linked records. Existing mismatches
-- deliberately stop this migration so they can be investigated before release.

alter table public.role_assignments
  add constraint role_assignments_venue_member_fk foreign key (venue_id, user_id)
    references public.venue_memberships(venue_id, user_id) on delete cascade;
alter table public.department_memberships
  add constraint department_memberships_venue_member_fk foreign key (venue_id, user_id)
    references public.venue_memberships(venue_id, user_id) on delete cascade;

alter table public.service_requests
  add constraint service_requests_venue_id_id_key unique (venue_id, id),
  add constraint service_requests_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint service_requests_venue_assignee_fk foreign key (venue_id, assigned_user_id)
    references public.venue_memberships(venue_id, user_id)
    on delete set null (assigned_user_id);
alter table public.service_request_history
  add constraint request_history_venue_request_fk foreign key (venue_id, request_id)
    references public.service_requests(venue_id, id) on delete cascade;

alter table public.event_tasks
  add constraint event_tasks_venue_id_id_key unique (venue_id, id),
  add constraint event_tasks_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;

alter table public.venue_suites
  add constraint venue_suites_venue_id_id_key unique (venue_id, id);
alter table public.suite_event_assignments
  add constraint suite_assignments_venue_id_id_key unique (venue_id, id),
  add constraint suite_assignments_venue_event_id_id_key unique (venue_id, event_id, id),
  add constraint suite_assignments_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint suite_assignments_venue_suite_fk foreign key (venue_id, suite_id)
    references public.venue_suites(venue_id, id) on delete cascade;
alter table public.suite_state_history
  add constraint suite_history_venue_assignment_fk foreign key (venue_id, assignment_id)
    references public.suite_event_assignments(venue_id, id) on delete cascade;

alter table public.event_staff
  add constraint event_staff_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint event_staff_venue_user_fk foreign key (venue_id, user_id)
    references public.venue_memberships(venue_id, user_id)
    on delete set null (user_id),
  add constraint event_staff_event_suite_fk foreign key (venue_id, event_id, suite_assignment_id)
    references public.suite_event_assignments(venue_id, event_id, id)
    on delete set null (suite_assignment_id);
alter table public.event_briefings
  add constraint event_briefings_venue_id_id_key unique (venue_id, id),
  add constraint event_briefings_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.briefing_acknowledgments
  add constraint briefing_acks_venue_briefing_fk foreign key (venue_id, briefing_id)
    references public.event_briefings(venue_id, id) on delete cascade;

alter table public.beo_documents
  add constraint beo_documents_venue_id_id_key unique (venue_id, id),
  add constraint beo_documents_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.beo_revisions
  add constraint beo_revisions_venue_id_id_key unique (venue_id, id),
  add constraint beo_revisions_venue_beo_id_id_key unique (venue_id, beo_id, id),
  add constraint beo_revisions_venue_document_fk foreign key (venue_id, beo_id)
    references public.beo_documents(venue_id, id) on delete cascade;
alter table public.beo_documents
  add constraint beo_documents_current_revision_fk
    foreign key (venue_id, id, current_revision_id)
    references public.beo_revisions(venue_id, beo_id, id);
alter table public.beo_acknowledgments
  add constraint beo_acks_venue_revision_fk foreign key (venue_id, revision_id)
    references public.beo_revisions(venue_id, id) on delete cascade;

alter table public.banquet_timeline_items
  add constraint timeline_venue_id_id_key unique (venue_id, id),
  add constraint timeline_venue_event_id_id_key unique (venue_id, event_id, id),
  add constraint timeline_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint timeline_same_event_dependency_fk foreign key (venue_id, event_id, depends_on)
    references public.banquet_timeline_items(venue_id, event_id, id)
    on delete set null (depends_on);
alter table public.event_menu_items
  add constraint menu_items_venue_event_id_id_key unique (venue_id, event_id, id),
  add constraint menu_items_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.culinary_batches
  add constraint culinary_batches_venue_id_id_key unique (venue_id, id),
  add constraint culinary_batches_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint culinary_batches_same_event_menu_fk foreign key (venue_id, event_id, menu_item_id)
    references public.event_menu_items(venue_id, event_id, id)
    on delete set null (menu_item_id);
alter table public.culinary_batch_history
  add constraint culinary_history_venue_batch_fk foreign key (venue_id, batch_id)
    references public.culinary_batches(venue_id, id) on delete cascade;

alter table public.inspection_instances
  add constraint inspection_instances_venue_id_id_key unique (venue_id, id),
  add constraint inspection_instances_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.inspection_responses
  add constraint inspection_responses_venue_instance_fk foreign key (venue_id, instance_id)
    references public.inspection_instances(venue_id, id) on delete cascade;

do $$
begin
  if exists (
    select 1 from public.inspection_instances i
    join public.checklist_templates t on t.id = i.template_id
    where t.venue_id is not null and t.venue_id <> i.venue_id
  ) or exists (
    select 1 from public.inspection_responses r
    join public.inspection_instances i on i.id = r.instance_id
    join public.checklist_items item on item.id = r.item_id
    where item.template_id <> i.template_id
  ) then
    raise exception 'Existing inspection template or response crosses a venue or template';
  end if;
end;
$$;

-- A shared checklist has no venue; a venue checklist must match the inspection.
create or replace function public.check_inspection_template_venue()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare template_venue uuid;
begin
  select venue_id into template_venue from public.checklist_templates
   where id = new.template_id;
  if not found or (template_venue is not null and template_venue <> new.venue_id) then
    raise exception 'Checklist template does not belong to this venue'
      using errcode = '23503';
  end if;
  return new;
end;
$$;
create trigger inspection_template_venue_guard
before insert or update of venue_id, template_id on public.inspection_instances
for each row execute function public.check_inspection_template_venue();

create or replace function public.check_inspection_response_item()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.inspection_instances i
    join public.checklist_items item on item.template_id = i.template_id
    where i.id = new.instance_id and item.id = new.item_id
  ) then
    raise exception 'Checklist item does not belong to this inspection'
      using errcode = '23503';
  end if;
  return new;
end;
$$;
create trigger inspection_response_item_guard
before insert or update of instance_id, item_id on public.inspection_responses
for each row execute function public.check_inspection_response_item();

alter table public.event_announcements
  add constraint event_announcements_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.task_comments
  add constraint task_comments_venue_task_fk foreign key (venue_id, task_id)
    references public.event_tasks(venue_id, id) on delete cascade;
alter table public.notifications
  add constraint notifications_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint notifications_venue_user_fk foreign key (venue_id, user_id)
    references public.venue_memberships(venue_id, user_id) on delete cascade;
alter table public.operational_incidents
  add constraint operational_incidents_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;
alter table public.event_closeouts
  add constraint event_closeouts_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade;

-- event_spaces previously had no venue_id. Populate it from its event and
-- require both sides of the association to belong to that venue.
alter table public.event_spaces add column venue_id uuid;
update public.event_spaces es set venue_id = e.venue_id
  from public.events e where e.id = es.event_id;
alter table public.event_spaces
  alter column venue_id set not null,
  add constraint event_spaces_venue_event_fk foreign key (venue_id, event_id)
    references public.events(venue_id, id) on delete cascade,
  add constraint event_spaces_venue_space_fk foreign key (venue_id, venue_space_id)
    references public.venue_spaces(venue_id, id) on delete cascade;

-- Inspection creation must begin open and without fabricated sign-offs.
alter policy inspections_insert on public.inspection_instances
  with check (
    public.has_permission(venue_id, 'run_inspections')
    and status = 'open'
    and completed_by is null and completed_at is null
    and approved_by is null and approved_at is null
  );
