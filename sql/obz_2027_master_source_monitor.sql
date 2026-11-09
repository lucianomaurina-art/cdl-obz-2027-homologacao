create table if not exists public.obz_master_sources (
 source_key text primary key,
 spreadsheet_id text not null,
 sheet_gid bigint not null,
 source_url text not null,
 last_checked_at timestamptz,
 last_status text not null default 'unverified' check(last_status in ('unverified','in_sync','divergent','unavailable')),
 last_diff jsonb not null default '{}'::jsonb,
 last_error text,
 last_source_hash text,
 updated_at timestamptz not null default now()
);
alter table public.obz_master_sources enable row level security;
revoke all on public.obz_master_sources from anon,authenticated;
grant select on public.obz_master_sources to authenticated;
drop policy if exists obz_master_sources_read_admin on public.obz_master_sources;
create policy obz_master_sources_read_admin on public.obz_master_sources
 for select to authenticated using(public.obz_is_admin());
insert into public.obz_master_sources(source_key,spreadsheet_id,sheet_gid,source_url)
values('OBZ2027','1MiRtyjsR4plGiaone1x-89DcyMX8UzsDmVKptzKZ9E4',587542658,'https://docs.google.com/spreadsheets/d/1MiRtyjsR4plGiaone1x-89DcyMX8UzsDmVKptzKZ9E4/edit?gid=587542658')
on conflict(source_key) do nothing;
comment on table public.obz_master_sources is 'Controle de divergências entre Google Sheets e rubricas OBZ; leitura administrativa e atualização apenas via Edge Function autorizada.';