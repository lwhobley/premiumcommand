-- Run after migration 0029. The transaction rolls back all test rows.
begin;

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_other_venue uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_event uuid;
  v_closed uuid;
  v_foreign_event uuid;
  v_suite uuid;
  v_assignment uuid;
  v_note uuid;
  v_closed_note uuid;
  v_applied meeting_notes;
  v_ev events;
  v_n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'notes-director@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_manager, 'authenticated', 'authenticated', 'notes-manager@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'notes-runner@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_outsider, 'authenticated', 'authenticated', 'notes-outsider@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Meeting notes test');
  insert into public.venues (id, organization_id, name) values
    (v_venue, v_org, 'Notes arena'), (v_other_venue, v_org, 'Other arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_manager), (v_venue, v_runner), (v_other_venue, v_outsider);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_manager, 'premium_manager'),
    (v_venue, v_runner, 'runner'), (v_other_venue, v_outsider, 'director');

  insert into public.events (venue_id, name, event_type, service_start, service_end, guaranteed_guests, status)
    values (v_venue, 'Hawks vs. Stars', 'hockey_game', '2026-10-18 00:00+00', '2026-10-18 04:00+00', 150, 'planning')
    returning id into v_event;
  insert into public.events (venue_id, name, event_type, service_start, service_end, status)
    values (v_venue, 'Last week', 'concert', '2026-10-01 00:00+00', '2026-10-01 04:00+00', 'closed')
    returning id into v_closed;
  insert into public.events (venue_id, name, event_type, service_start, service_end)
    values (v_other_venue, 'Elsewhere', 'concert', '2026-10-20 00:00+00', '2026-10-20 04:00+00')
    returning id into v_foreign_event;
  insert into public.venue_suites (venue_id, name) values (v_venue, 'Suite 12') returning id into v_suite;
  insert into public.suite_event_assignments (venue_id, event_id, suite_id, dietary_notes)
    values (v_venue, v_event, v_suite, '') returning id into v_assignment;
  insert into public.event_staff (venue_id, event_id, display_name, user_id)
    values (v_venue, v_event, 'Runner', v_runner);

  -- A manager without administrator access cannot create a note.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.meeting_notes (venue_id, body) values (v_venue, 'Manager note');
    raise exception 'A manager created a meeting note';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- The administrator creates a draft and records a proposal.
  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.meeting_notes (venue_id, title, body)
    values (v_venue, 'Hawks walkthrough', 'Client confirmed 180 guests. Suite 12 host has a nut allergy.')
    returning id into v_note;
  update public.meeting_notes set analysis = '{"changes": []}', status = 'analyzed', event_id = v_event
   where id = v_note;

  -- A note cannot point at another venue's event.
  begin
    insert into public.meeting_notes (venue_id, body, event_id) values (v_venue, 'Wrong venue', v_foreign_event);
    raise exception 'A note was linked to another venue''s event';
  exception when foreign_key_violation then null;
  end;

  -- Applied fields are written only by apply_meeting_note.
  begin
    update public.meeting_notes set status = 'applied' where id = v_note;
    raise exception 'A note was marked applied directly';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.meeting_notes set summary = 'Forged' where id = v_note;
    raise exception 'A summary was written directly';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- Drafts are hidden from non-administrators.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.meeting_notes where id = v_note;
  if v_n <> 0 then raise exception 'A runner can read a draft meeting note'; end if;
  reset role;

  -- Only administrators of the note's venue can apply it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', '[]');
    raise exception 'A manager applied a meeting note';
  exception when insufficient_privilege then null;
  end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', '[]');
    raise exception 'Another venue''s director applied a meeting note';
  exception when insufficient_privilege then null;
  end;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- One bad change fails the whole call and nothing is changed.
  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', jsonb_build_array(
      jsonb_build_object('type', 'update_event', 'field', 'guaranteed_guests', 'value', '180'),
      jsonb_build_object('type', 'add_task', 'department', 'operations', 'title', 'Should roll back'),
      jsonb_build_object('type', 'drop_table')));
    raise exception 'An unknown change type was accepted';
  exception when invalid_parameter_value then null;
  end;
  select * into v_ev from public.events where id = v_event;
  select count(*) into v_n from public.event_tasks where event_id = v_event;
  if v_ev.guaranteed_guests <> 150 or v_n <> 0 then raise exception 'A failed apply left a partial change'; end if;

  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', jsonb_build_array(
      jsonb_build_object('type', 'update_event', 'field', 'guaranteed_guests', 'value', 'about 200')));
    raise exception 'A non-numeric guest count was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', jsonb_build_array(
      jsonb_build_object('type', 'update_event', 'field', 'service_end', 'value', '2026-10-17T00:00:00Z')));
    raise exception 'Service end before start was accepted';
  exception when check_violation then null;
  end;
  begin
    perform public.apply_meeting_note(v_note, v_event, 'x', '{}', jsonb_build_array(
      jsonb_build_object('type', 'update_suite', 'assignment_id', gen_random_uuid(),
        'field', 'dietary_notes', 'value', 'x')));
    raise exception 'A suite outside the event was changed';
  exception when no_data_found then null;
  end;

  -- A full apply makes every accepted change.
  v_applied := public.apply_meeting_note(v_note, v_event,
    '  Headcount rises to 180.  ', array['180 guests', '  ', 'Nut allergy in Suite 12'],
    jsonb_build_array(
      jsonb_build_object('type', 'update_event', 'field', 'guaranteed_guests', 'value', '180', 'reason', 'r'),
      jsonb_build_object('type', 'update_event', 'field', 'service_start', 'value', '2026-10-17T18:30-05:00'),
      jsonb_build_object('type', 'append_event_notes', 'text', 'Client prefers still water.'),
      jsonb_build_object('type', 'add_task', 'department', 'culinary', 'title', 'Plan nut-free dessert',
        'is_required', true, 'due_at', '2026-10-17T12:00-05:00'),
      jsonb_build_object('type', 'post_announcement', 'body', 'Suite 12 host has a nut allergy.'),
      jsonb_build_object('type', 'add_menu_item', 'name', 'Sorbet', 'course', 'Dessert',
        'dietary_tags', jsonb_build_array('vegan', ' '), 'allergens', ''),
      jsonb_build_object('type', 'update_suite', 'assignment_id', v_assignment,
        'field', 'dietary_notes', 'value', 'Host: nut allergy')));

  if v_applied.status <> 'applied' or v_applied.applied_by <> v_director or v_applied.event_id <> v_event then
    raise exception 'The note was not marked applied';
  end if;
  if v_applied.summary <> 'Headcount rises to 180.' or v_applied.key_details <> array['180 guests', 'Nut allergy in Suite 12'] then
    raise exception 'Summary or key details were not cleaned: % %', v_applied.summary, v_applied.key_details;
  end if;
  if jsonb_array_length(v_applied.applied_actions) <> 7 then raise exception 'Applied changes were not recorded'; end if;

  select * into v_ev from public.events where id = v_event;
  if v_ev.guaranteed_guests <> 180 then raise exception 'Guest count was not updated'; end if;
  if v_ev.service_start <> '2026-10-17 23:30+00'::timestamptz then raise exception 'Service start was not updated'; end if;
  if v_ev.notes <> 'Client prefers still water.' then raise exception 'Event notes were not appended'; end if;
  if v_ev.version <> 2 then raise exception 'Event version was %, expected 2', v_ev.version; end if;
  if v_ev.status <> 'planning' then raise exception 'Event status changed'; end if;

  select count(*) into v_n from public.event_tasks
   where event_id = v_event and department = 'culinary' and title = 'Plan nut-free dessert'
     and is_required and status = 'not_started' and due_at = '2026-10-17 17:00+00';
  if v_n <> 1 then raise exception 'The task was not added'; end if;
  select count(*) into v_n from public.event_menu_items
   where event_id = v_event and name = 'Sorbet' and dietary_tags = array['vegan'];
  if v_n <> 1 then raise exception 'The menu item was not added'; end if;
  select count(*) into v_n from public.suite_event_assignments
   where id = v_assignment and dietary_notes = 'Host: nut allergy' and version = 2;
  if v_n <> 1 then raise exception 'The suite was not updated'; end if;

  -- An applied note cannot be applied again, edited, or deleted.
  begin
    perform public.apply_meeting_note(v_note, v_event, 'again', '{}', '[]');
    raise exception 'A note was applied twice';
  exception when check_violation then null;
  end;
  update public.meeting_notes set title = 'Edited' where id = v_note;
  delete from public.meeting_notes where id = v_note;
  select count(*) into v_n from public.meeting_notes where id = v_note and title = 'Hawks walkthrough';
  if v_n <> 1 then raise exception 'An applied note was edited or deleted'; end if;

  -- A closed event takes the note as a record, but no changes.
  insert into public.meeting_notes (venue_id, body) values (v_venue, 'Recap of last week') returning id into v_closed_note;
  begin
    perform public.apply_meeting_note(v_closed_note, v_closed, 'x', '{}', jsonb_build_array(
      jsonb_build_object('type', 'append_event_notes', 'text', 'Late change')));
    raise exception 'A closed event was changed';
  exception when check_violation then null;
  end;
  v_applied := public.apply_meeting_note(v_closed_note, v_closed, 'Recap', '{}', '[]');
  if v_applied.status <> 'applied' then raise exception 'A closed event could not take a note on record'; end if;
  reset role;

  -- Everyone at the venue can read applied notes. Other venues cannot.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.meeting_notes where id = v_note;
  if v_n <> 1 then raise exception 'A venue member cannot read an applied note'; end if;
  select count(*) into v_n from public.notifications where user_id = v_runner and event_id = v_event and kind = 'announcement';
  if v_n <> 1 then raise exception 'Rostered staff were not notified of the announcement'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.meeting_notes where venue_id = v_venue;
  if v_n <> 0 then raise exception 'Another venue can read meeting notes'; end if;
  reset role;

  select count(*) into v_n from public.audit_logs where entity = 'meeting_note' and entity_id = v_note;
  if v_n <> 1 then raise exception 'The apply was not audited'; end if;

  -- Removing an event keeps its notes, unlinked.
  delete from public.events where id = v_closed;
  select count(*) into v_n from public.meeting_notes where id = v_closed_note and event_id is null and venue_id = v_venue;
  if v_n <> 1 then raise exception 'Deleting the event did not unlink its note'; end if;
end;
$$;

rollback;
