-- Run after migration 0033. The transaction rolls back all test rows.
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
  v_manager uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_path text;
  v_n integer;
begin
  insert into auth.users (id, aud, role, email, instance_id) values
    (v_director, 'authenticated', 'authenticated', 'docs-director@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_manager, 'authenticated', 'authenticated', 'docs-manager@example.invalid', '00000000-0000-0000-0000-000000000000'),
    (v_outsider, 'authenticated', 'authenticated', 'docs-outsider@example.invalid', '00000000-0000-0000-0000-000000000000');
  insert into public.organizations (id, name) values (v_org, 'Documents test');
  insert into public.venues (id, organization_id, name) values
    (v_venue, v_org, 'Docs arena'), (v_other_venue, v_org, 'Other arena');
  insert into public.venue_memberships (venue_id, user_id) values
    (v_venue, v_director), (v_venue, v_manager), (v_other_venue, v_outsider);
  insert into public.role_assignments (venue_id, user_id, role_code) values
    (v_venue, v_director, 'director'), (v_venue, v_manager, 'premium_manager'),
    (v_other_venue, v_outsider, 'director');
  v_path := v_venue || '/' || gen_random_uuid() || '/beo.pdf';

  -- An administrator can upload, read, and delete a document in the venue's folder.
  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into storage.objects (bucket_id, name) values ('documents', v_path);
  select count(*) into v_n from storage.objects where bucket_id = 'documents' and name = v_path;
  if v_n <> 1 then raise exception 'An administrator cannot read their upload'; end if;
  begin
    insert into storage.objects (bucket_id, name) values ('documents', 'not-a-venue/x/beo.pdf');
    raise exception 'A document was stored outside a venue folder';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- A manager without administrator access cannot upload or read documents.
  perform set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name) values ('documents', v_venue || '/' || gen_random_uuid() || '/menu.pdf');
    raise exception 'A manager uploaded a document';
  exception when insufficient_privilege then null;
  end;
  select count(*) into v_n from storage.objects where bucket_id = 'documents';
  if v_n <> 0 then raise exception 'A manager can read documents'; end if;
  reset role;

  -- Another venue's administrator cannot see or delete it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from storage.objects where bucket_id = 'documents';
  if v_n <> 0 then raise exception 'Another venue can read documents'; end if;
  delete from storage.objects where bucket_id = 'documents' and name = v_path;
  reset role;
  select count(*) into v_n from storage.objects where bucket_id = 'documents' and name = v_path;
  if v_n <> 1 then raise exception 'Another venue deleted a document'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_director, 'role', 'authenticated')::text, true);
  set local role authenticated;
  delete from storage.objects where bucket_id = 'documents' and name = v_path;
  reset role;
  select count(*) into v_n from storage.objects where bucket_id = 'documents' and name = v_path;
  if v_n <> 0 then raise exception 'The administrator could not delete the document'; end if;
end;
$$;

rollback;
