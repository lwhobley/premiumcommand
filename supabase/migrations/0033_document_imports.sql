-- Private storage for BEO and menu documents read by the document-ai Edge Function.
--
-- An administrator uploads a PDF, photo, or text file; the function reads it as that
-- administrator, asks Claude to extract the BEO or menu, and deletes the file. Nothing
-- is written to the event until the administrator reviews the result and saves it
-- through the usual BEO and menu rules.
--
-- Object path convention: {venue_id}/{event_id}/{file}. Only administrators of that
-- venue (manage_configuration) can write, read, or delete.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documents', 'documents', false, 10485760,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain']
)
on conflict (id) do nothing;

create policy documents_read on storage.objects for select to authenticated
  using (
    bucket_id = 'documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
             else false end
  );

create policy documents_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
             else false end
  );

create policy documents_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
             else false end
  );
