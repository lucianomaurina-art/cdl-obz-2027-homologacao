-- CDL NH | OBZ 2027 | Vinculacao de pacotes a objetivos, resultados-chave e metas do portfolio
-- Sem alteracoes nas 366 rubricas financeiras; sem vinculacoes automaticas.
create table if not exists public.obz_strategy_objectives (
 code text primary key,
 fiscal_year integer not null default 2027,
 perspective text not null default '',
 title text not null,
 source_url text not null,
 source_row integer not null,
 created_at timestamptz not null default now()
);
create table if not exists public.obz_strategy_krs (
 code text primary key,
 objective_code text not null references public.obz_strategy_objectives(code),
 fiscal_year integer not null default 2027,
 result_text text not null,
 indicator text not null default '',
 baseline_2026 text not null default '',
 target_2027 text not null default '',
 source_url text not null,
 source_row integer not null,
 created_at timestamptz not null default now()
);
create table if not exists public.obz_portfolio_targets (
 target_key text primary key,
 service_code text not null,
 service_name text not null,
 category text not null default '',
 metric text not null,
 baseline_2026 text not null default '',
 target_2027 text not null default '',
 fiscal_year integer not null default 2027,
 source_url text not null,
 source_row integer not null,
 created_at timestamptz not null default now()
);
create table if not exists public.obz_center_strategy_links (
 id uuid primary key default gen_random_uuid(),
 center_id uuid not null references public.obz_centers(id) on delete restrict,
 objective_code text references public.obz_strategy_objectives(code) on delete restrict,
 kr_code text references public.obz_strategy_krs(code) on delete restrict,
 portfolio_key text references public.obz_portfolio_targets(target_key) on delete restrict,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint obz_strategy_one_target check (num_nonnulls(objective_code,kr_code,portfolio_key)=1)
);
create unique index if not exists obz_strategy_center_objective_unique on public.obz_center_strategy_links(center_id,objective_code) where objective_code is not null;
create unique index if not exists obz_strategy_center_kr_unique on public.obz_center_strategy_links(center_id,kr_code) where kr_code is not null;
create unique index if not exists obz_strategy_center_portfolio_unique on public.obz_center_strategy_links(center_id,portfolio_key) where portfolio_key is not null;
create index if not exists obz_strategy_links_center_idx on public.obz_center_strategy_links(center_id);
alter table public.obz_strategy_objectives enable row level security;
alter table public.obz_strategy_krs enable row level security;
alter table public.obz_portfolio_targets enable row level security;
alter table public.obz_center_strategy_links enable row level security;
create policy obz_strategy_objectives_read on public.obz_strategy_objectives
 for select to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.active=true));
create policy obz_strategy_krs_read on public.obz_strategy_krs
 for select to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.active=true));
create policy obz_portfolio_targets_read on public.obz_portfolio_targets
 for select to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.active=true));
create policy obz_center_strategy_links_read on public.obz_center_strategy_links
 for select to authenticated using (public.obz_can_manage(center_id));
create policy obz_center_strategy_links_insert on public.obz_center_strategy_links
 for insert to authenticated with check (
 created_by=auth.uid() and public.obz_can_manage(center_id)
 and exists(select 1 from public.obz_centers c where c.id=center_id and c.status in ('draft','changes_requested'))
 );
create policy obz_center_strategy_links_delete on public.obz_center_strategy_links
 for delete to authenticated using (
 public.obz_can_manage(center_id)
 and exists(select 1 from public.obz_centers c where c.id=center_id and c.status in ('draft','changes_requested'))
 );
revoke all on public.obz_strategy_objectives,public.obz_strategy_krs,public.obz_portfolio_targets,public.obz_center_strategy_links from anon;
grant select on public.obz_strategy_objectives,public.obz_strategy_krs,public.obz_portfolio_targets to authenticated;
grant select,insert,delete on public.obz_center_strategy_links to authenticated;
create or replace function public.obz_audit_strategy_link()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_center uuid;
begin
 v_center:=case when tg_op='DELETE' then old.center_id else new.center_id end;
 insert into public.obz_audit(center_id,actor_id,action,old_value,new_value)
 values(v_center,auth.uid(),
   case when tg_op='DELETE' then 'strategy_link_removed' else 'strategy_link_added' end,
   case when tg_op='DELETE' then to_jsonb(old) else null end,
   case when tg_op='INSERT' then to_jsonb(new) else null end);
 return case when tg_op='DELETE' then old else new end;
end; $$;
revoke execute on function public.obz_audit_strategy_link() from public,anon,authenticated;
drop trigger if exists obz_center_strategy_link_audit on public.obz_center_strategy_links;
create trigger obz_center_strategy_link_audit after insert or delete on public.obz_center_strategy_links
 for each row execute function public.obz_audit_strategy_link();