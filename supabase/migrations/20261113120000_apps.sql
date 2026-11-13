-- App- en link-tegels in Tools.
alter table public.records drop constraint if exists records_kind_check;
alter table public.records add constraint records_kind_check
  check (kind in ('calendar', 'job', 'note', 'photo', 'hours', 'doc', 'app'));
