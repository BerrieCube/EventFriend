-- Documenten (callsheets per klus, bibliotheek) en links.
alter table public.records drop constraint if exists records_kind_check;
alter table public.records add constraint records_kind_check
  check (kind in ('calendar', 'job', 'note', 'photo', 'hours', 'doc'));

insert into storage.buckets (id, name, public, file_size_limit)
values ('files', 'files', false, 52428800)
on conflict (id) do nothing;

drop policy if exists "eigen bestanden lezen" on storage.objects;
create policy "eigen bestanden lezen" on storage.objects
  for select to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen bestanden uploaden" on storage.objects;
create policy "eigen bestanden uploaden" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen bestanden wijzigen" on storage.objects;
create policy "eigen bestanden wijzigen" on storage.objects
  for update to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen bestanden verwijderen" on storage.objects;
create policy "eigen bestanden verwijderen" on storage.objects
  for delete to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = (select auth.uid())::text);
