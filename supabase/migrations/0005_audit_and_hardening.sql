-- CUTX Premium Command: Phase 4 hardening.
-- Structured audit trail for every workflow state change.

-- Records the workflow state of the changed row, never its free-text content.
create or replace function public.audit_workflow_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  row_json jsonb := to_jsonb(new);
  old_json jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  venue uuid := (row_json ->> 'venue_id')::uuid;
begin
  -- Skip updates that do not change workflow state, so the log stays readable.
  if tg_op = 'UPDATE'
     and (row_json ->> 'status') is not distinct from (old_json ->> 'status')
     and (row_json ->> 'state') is not distinct from (old_json ->> 'state')
     and (row_json ->> 'version') is not distinct from (old_json ->> 'version') then
    return new;
  end if;

  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (
    venue,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    (row_json ->> 'id')::uuid,
    jsonb_strip_nulls(jsonb_build_object(
      'status', row_json ->> 'status',
      'previous_status', old_json ->> 'status',
      'state', row_json ->> 'state',
      'previous_state', old_json ->> 'state',
      'version', row_json ->> 'version'
    ))
  );
  return new;
end;
$$;

revoke execute on function public.audit_workflow_change() from public, anon, authenticated;

create trigger service_requests_audit
after insert or update on service_requests
for each row execute function public.audit_workflow_change();

create trigger beo_revisions_audit
after insert or update on beo_revisions
for each row execute function public.audit_workflow_change();

create trigger suite_assignments_audit
after update on suite_event_assignments
for each row execute function public.audit_workflow_change();

create trigger culinary_batches_audit
after update on culinary_batches
for each row execute function public.audit_workflow_change();

create trigger banquet_timeline_audit
after update on banquet_timeline_items
for each row execute function public.audit_workflow_change();

create trigger inspection_instances_audit
after update on inspection_instances
for each row execute function public.audit_workflow_change();

create trigger event_closeouts_audit
after update on event_closeouts
for each row execute function public.audit_workflow_change();

-- Audit rows are readable only by people who can view reports.
-- (audit_logs_read from migration 0001 already enforces view_reports.)
