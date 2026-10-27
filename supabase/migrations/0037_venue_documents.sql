-- Venue documents: a read-only reference library on the Documents page.
--
-- Administrators (manage_configuration) add PDFs, photos, and text files. Everyone at the
-- venue can view them inside the app, which shows them in its own viewer with no download,
-- share, or print controls. Files are kept in their own private bucket, apart from the
-- `documents` bucket that the BEO and menu import empties after reading.
--
-- Object path convention: {venue_id}/{file}. Each file has one venue_documents row that
-- names it; the row is what the Documents page lists.

-- ---- 1. Storage ----------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'venue-documents', 'venue-documents', false, 26214400,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain']
)
on conflict (id) do nothing;

create policy venue_documents_object_read on storage.objects for select to authenticated
  using (
    bucket_id = 'venue-documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.is_venue_member(((storage.foldername(name))[1])::uuid)
             else false end
  );

create policy venue_documents_object_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'venue-documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
             else false end
  );

create policy venue_documents_object_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'venue-documents'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
             then public.has_permission(((storage.foldername(name))[1])::uuid, 'manage_configuration')
             else false end
  );

-- ---- 2. Table and access -----------------------------------------------------------------

create table public.venue_documents (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 160),
  category text not null default '' check (length(category) <= 60),
  file_name text not null check (length(file_name) between 1 and 255),
  -- Always inside the venue's own folder, so a row cannot point at another venue's file.
  storage_path text not null unique
    check (storage_path like venue_id::text || '/%' and storage_path !~ '\.\.'),
  mime_type text not null
    check (mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain')),
  size_bytes bigint not null check (size_bytes between 1 and 26214400),
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index venue_documents_venue_idx on public.venue_documents(venue_id, category, title);

alter table public.venue_documents enable row level security;
grant select, insert, update, delete on public.venue_documents to authenticated;

create policy venue_documents_read on public.venue_documents for select to authenticated
  using (public.is_venue_member(venue_id));
create policy venue_documents_insert on public.venue_documents for insert to authenticated
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_documents_update on public.venue_documents for update to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'))
  with check (public.has_permission(venue_id, 'manage_configuration'));
create policy venue_documents_delete on public.venue_documents for delete to authenticated
  using (public.has_permission(venue_id, 'manage_configuration'));

-- Only the title and category can change after upload; the file it names stays fixed.
-- uploaded_by may only be cleared, which is what deleting the uploader's account does.
create or replace function public.venue_documents_guard()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if new.venue_id <> old.venue_id
     or new.storage_path <> old.storage_path
     or new.file_name <> old.file_name
     or new.mime_type <> old.mime_type
     or new.size_bytes <> old.size_bytes
     or (new.uploaded_by is not null and new.uploaded_by is distinct from old.uploaded_by)
     or new.created_at <> old.created_at then
    raise exception 'Only a document''s title and category can be changed'
      using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function public.venue_documents_guard() from public, anon, authenticated;

create trigger venue_documents_guard_trg
before update on public.venue_documents
for each row execute function public.venue_documents_guard();

-- Every document added, renamed, or removed is recorded, with the title it applied to.
create or replace function public.venue_documents_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  row_data venue_documents%rowtype;
begin
  row_data := case when tg_op = 'DELETE' then old else new end;
  insert into audit_logs (venue_id, action, entity, entity_id, details)
  values (row_data.venue_id, 'venue_document.' || lower(tg_op), 'venue_document', row_data.id,
          jsonb_build_object('title', row_data.title, 'file_name', row_data.file_name));
  return row_data;
end;
$$;

revoke execute on function public.venue_documents_audit() from public, anon, authenticated;

create trigger venue_documents_audit_trg
after insert or update or delete on public.venue_documents
for each row execute function public.venue_documents_audit();
