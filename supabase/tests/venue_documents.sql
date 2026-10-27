-- Run after migration 0037. The transaction rolls back all test rows.
begin;

-- Newer Storage versions block direct deletes unless this setting is on. It lasts only for this
-- transaction, and the delete policies are still the thing under test.
select set_config('storage.allow_delete_query', 'true', true);

do $$
declare
  v_org uuid := gen_random_uuid();
  v_venue uuid := gen_random_uuid();
  v_other_venue uuid := gen_random_uuid();
  v_director uuid := gen_random_uuid();
  v_runner uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_path text;
  v_doc uuid;
  v_n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'library-director@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_runner, 'authenticated', 'authenticated', 'library-runner@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_outsider, 'authenticated', 'authenticated', 'library-outsider@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Library test');
  insert into public.venues (id, organization_id, name) values
    (v_venue, v_org, 'Library arena'), (v_other_venue, v_org, 'Other arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_runner), (v_other_venue, v_outsider);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_runner, 'runner'),
    (v_other_venue, v_outsider, 'director');
  v_path := v_venue || '/' || gen_random_uuid() || '.pdf';

  -- An administrator adds a document and renames it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into storage.objects (bucket_id, name) values ('venue-documents', v_path);
  insert into public.venue_documents (venue_id, title, file_name, storage_path, mime_type, size_bytes)
  values (v_venue, 'Standards', 'standards.pdf', v_path, 'application/pdf', 1024)
  returning id into v_doc;
  update public.venue_documents set title = 'Service Standards', category = 'Policies' where id = v_doc;
  begin
    update public.venue_documents set storage_path = v_venue || '/other.pdf' where id = v_doc;
    raise exception 'A document was pointed at another file';
  exception when check_violation then null;
  end;
  begin
    insert into public.venue_documents (venue_id, title, file_name, storage_path, mime_type, size_bytes)
    values (v_venue, 'Elsewhere', 'x.pdf', v_other_venue || '/x.pdf', 'application/pdf', 1);
    raise exception 'A document named a file in another venue''s folder';
  exception when check_violation then null;
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('venue-documents', 'not-a-venue/x.pdf');
    raise exception 'A file was stored outside a venue folder';
  exception when insufficient_privilege then null;
  end;
  reset role;

  select count(*) into v_n from public.audit_logs where entity = 'venue_document' and entity_id = v_doc;
  if v_n <> 2 then raise exception 'Expected 2 audit entries, found %', v_n; end if;

  -- A runner can see the document and its file, but cannot add, change, or remove either.
  perform set_config('request.jwt.claims', json_build_object('sub', v_runner, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.venue_documents where venue_id = v_venue;
  if v_n <> 1 then raise exception 'A runner cannot see documents'; end if;
  select count(*) into v_n from storage.objects where bucket_id = 'venue-documents' and name = v_path;
  if v_n <> 1 then raise exception 'A runner cannot read the file'; end if;
  update public.venue_documents set title = 'Changed' where id = v_doc;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'A runner renamed a document'; end if;
  delete from public.venue_documents where id = v_doc;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'A runner removed a document'; end if;
  begin
    insert into storage.objects (bucket_id, name) values ('venue-documents', v_venue || '/runner.pdf');
    raise exception 'A runner uploaded a file';
  exception when insufficient_privilege then null;
  end;
  delete from storage.objects where bucket_id = 'venue-documents' and name = v_path;
  reset role;
  select count(*) into v_n from storage.objects where bucket_id = 'venue-documents' and name = v_path;
  if v_n <> 1 then raise exception 'A runner deleted a file'; end if;

  -- Another venue sees nothing.
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.venue_documents;
  if v_n <> 0 then raise exception 'Another venue can see documents'; end if;
  select count(*) into v_n from storage.objects where bucket_id = 'venue-documents';
  if v_n <> 0 then raise exception 'Another venue can read files'; end if;
  reset role;

  -- Deleting an uploader's account keeps the document and clears who added it.
  insert into public.venue_documents (venue_id, title, file_name, storage_path, mime_type, size_bytes, uploaded_by)
  values (v_venue, 'Left behind', 'left.pdf', v_venue || '/left.pdf', 'application/pdf', 1, v_outsider);
  delete from auth.users where id = v_outsider;
  if (select uploaded_by from public.venue_documents where storage_path = v_venue || '/left.pdf') is not null then
    raise exception 'The deleted uploader is still recorded';
  end if;
  begin
    update public.venue_documents set uploaded_by = v_runner where storage_path = v_venue || '/left.pdf';
    raise exception 'A document''s uploader was reassigned';
  exception when check_violation then null;
  end;

  -- The administrator removes it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  delete from public.venue_documents where id = v_doc;
  delete from storage.objects where bucket_id = 'venue-documents' and name = v_path;
  reset role;
  select count(*) into v_n from storage.objects where bucket_id = 'venue-documents' and name = v_path;
  if v_n <> 0 then raise exception 'The administrator could not delete the file'; end if;

  raise notice 'Venue document checks passed';
end;
$$;

rollback;
