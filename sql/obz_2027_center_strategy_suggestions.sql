create table if not exists public.obz_center_strategy_proposals(
 center_id uuid primary key references public.obz_centers(id) on delete cascade,
 objectives text[] not null default '{}',
 krs text[] not null default '{}',
 portfolio_keys text[] not null default '{}',
 rationale text not null,
 source_note text not null default 'Planejamento Estratégico OBZ 2027 e Matriz de Gestão do Portfólio 2027',
 proposal_version integer not null default 1,
 proposed_at timestamptz not null default now(),
 constraint proposed_rationale_nonblank check(length(btrim(rationale))>10)
);
alter table public.obz_center_strategy_proposals enable row level security;
create policy obz_center_strategy_proposals_read on public.obz_center_strategy_proposals
 for select to authenticated using(public.obz_can_manage(center_id));
revoke all on public.obz_center_strategy_proposals from anon,authenticated;
grant select on public.obz_center_strategy_proposals to authenticated;
comment on table public.obz_center_strategy_proposals is 'Sugestão inicial não vinculante. Somente após o gestor confirmar e salvar na tabela obz_center_strategy_links os vínculos tornam-se efetivos.';