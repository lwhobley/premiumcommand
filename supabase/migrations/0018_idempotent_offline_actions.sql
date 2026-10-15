-- A queued action keeps one identity across retries. The server saves its first
-- result, so a lost HTTP response cannot turn a successful write into a conflict.
create table app_private.workflow_actions (
  id uuid primary key,
  user_id uuid not null,
  kind text not null,
  result jsonb,
  created_at timestamptz not null default now()
);
revoke all on app_private.workflow_actions from public, anon, authenticated;

create or replace function public.transition_service_request_once(
  p_action uuid, p_request uuid, p_to text, p_expected_version integer,
  p_note text default '', p_department text default null, p_user uuid default null
)
returns public.service_requests
language plpgsql security definer set search_path = public, app_private
as $$
declare
  action_row app_private.workflow_actions%rowtype;
  result_row public.service_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to continue' using errcode = '42501'; end if;
  insert into app_private.workflow_actions (id, user_id, kind)
  values (p_action, auth.uid(), 'request_transition') on conflict do nothing;
  select * into action_row from app_private.workflow_actions where id = p_action for update;
  if action_row.user_id <> auth.uid() or action_row.kind <> 'request_transition' then
    raise exception 'Action key belongs to another change' using errcode = '42501';
  end if;
  if action_row.result is not null then
    result_row := jsonb_populate_record(null::public.service_requests, action_row.result);
    return result_row;
  end if;
  result_row := public.transition_service_request(
    p_request, p_to, p_expected_version, p_note, p_department, p_user
  );
  update app_private.workflow_actions set result = to_jsonb(result_row) where id = p_action;
  return result_row;
end;
$$;
revoke execute on function public.transition_service_request_once(uuid, uuid, text, integer, text, text, uuid)
  from public, anon;
grant execute on function public.transition_service_request_once(uuid, uuid, text, integer, text, text, uuid)
  to authenticated;

alter table public.event_tasks add column version integer not null default 1;
create or replace function public.bump_task_version()
returns trigger language plpgsql set search_path = public as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;
create trigger bump_task_version before update on public.event_tasks
  for each row execute function public.bump_task_version();

create or replace function public.set_task_status_once(
  p_action uuid, p_task uuid, p_status text, p_expected_version integer
)
returns public.event_tasks
language plpgsql security definer set search_path = public, app_private
as $$
declare
  action_row app_private.workflow_actions%rowtype;
  task public.event_tasks%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to continue' using errcode = '42501'; end if;
  insert into app_private.workflow_actions (id, user_id, kind)
  values (p_action, auth.uid(), 'task_status') on conflict do nothing;
  select * into action_row from app_private.workflow_actions where id = p_action for update;
  if action_row.user_id <> auth.uid() or action_row.kind <> 'task_status' then
    raise exception 'Action key belongs to another change' using errcode = '42501';
  end if;
  if action_row.result is not null then
    task := jsonb_populate_record(null::public.event_tasks, action_row.result);
    return task;
  end if;
  select * into task from public.event_tasks where id = p_task for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if task.version <> p_expected_version then
    raise exception 'Conflict: task changed. Refresh and try again.' using errcode = '40001';
  end if;
  task := public.set_task_status(p_task, p_status);
  update app_private.workflow_actions set result = to_jsonb(task) where id = p_action;
  return task;
end;
$$;
revoke execute on function public.set_task_status(uuid, text) from authenticated;
revoke execute on function public.set_task_status_once(uuid, uuid, text, integer) from public, anon;
grant execute on function public.set_task_status_once(uuid, uuid, text, integer) to authenticated;
