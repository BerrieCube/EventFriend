-- EventFriend: synchronisatie tussen telefoon en web.
-- Alle gegevens (agenda's, eigen klussen, notities, foto-info, uren) staan
-- als JSON in één tabel, per gebruiker afgeschermd met Row Level Security.

create table if not exists public.records (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('calendar', 'job', 'note', 'photo', 'hours')),
  id text not null,
  data jsonb,
  deleted boolean not null default false,
  updated_at timestamptz not null,            -- tijdstip van wijzigen op het apparaat
  server_updated_at timestamptz not null default now(), -- voor ophalen van wijzigingen
  primary key (user_id, kind, id)
);

create index if not exists records_user_server_updated
  on public.records (user_id, server_updated_at);

create or replace function public.records_touch()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end $$;

drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
  for each row execute function public.records_touch();

alter table public.records enable row level security;

drop policy if exists "eigen records lezen" on public.records;
create policy "eigen records lezen" on public.records
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "eigen records toevoegen" on public.records;
create policy "eigen records toevoegen" on public.records
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "eigen records wijzigen" on public.records;
create policy "eigen records wijzigen" on public.records
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "eigen records verwijderen" on public.records;
create policy "eigen records verwijderen" on public.records
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Foto's: privé bucket, map per gebruiker (photos/<user_id>/<foto_id>.jpg).
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists "eigen fotos lezen" on storage.objects;
create policy "eigen fotos lezen" on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen fotos uploaden" on storage.objects;
create policy "eigen fotos uploaden" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen fotos wijzigen" on storage.objects;
create policy "eigen fotos wijzigen" on storage.objects
  for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "eigen fotos verwijderen" on storage.objects;
create policy "eigen fotos verwijderen" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
