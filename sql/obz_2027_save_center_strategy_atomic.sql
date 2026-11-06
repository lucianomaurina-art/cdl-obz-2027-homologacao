-- Salva TODOS os vínculos estratégicos de um pacote em uma única transação.
-- Um resultado-chave também determina automaticamente seu objetivo estratégico.
create or replace function public.obz_save_center_strategy(
 p_center uuid,
 p_objectives text[],
 p_krs text[],
 p_portfolio text[]
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 v_status text;
 v_objectives text[];
 v_krs text[];
 v_portfolio text[];
 v_actor uuid:=auth.uid();
begin
 if v_actor is null then raise exception 'Autenticação obrigatória'; end if;
 select status into v_status from public.obz_centers where id=p_center and fiscal_year=2027 for update;
 if not found then raise exception 'Pacote inexistente'; end if;
 if not public.obz_can_manage(p_center) then raise exception 'Acesso negado ao pacote'; end if;
 if v_status not in ('draft','changes_requested') then
  raise exception 'Vínculos bloqueados: pacote submetido ou aprovado';
 end if;
 v_krs:=array(select distinct x from unnest(coalesce(p_krs,ARRAY[]::text[])) x where x is not null and btrim(x)<>'');
 v_portfolio:=array(select distinct x from unnest(coalesce(p_portfolio,ARRAY[]::text[])) x where x is not null and btrim(x)<>'');
 v_objectives:=array(
  select distinct code from (
   select x as code from unnest(coalesce(p_objectives,ARRAY[]::text[])) x where x is not null and btrim(x)<>''
   union
   select k.objective_code from public.obz_strategy_krs k where k.code=any(v_krs)
  ) tmp
 );
 if cardinality(v_objectives)>6 or cardinality(v_krs)>24 or cardinality(v_portfolio)>40 then
  raise exception 'Quantidade de vínculos fora do limite';
 end if;
 if exists(select 1 from unnest(v_objectives) x where not exists(select 1 from public.obz_strategy_objectives o where o.code=x and o.fiscal_year=2027))
 or exists(select 1 from unnest(v_krs) x where not exists(select 1 from public.obz_strategy_krs k where k.code=x and k.fiscal_year=2027))
 or exists(select 1 from unnest(v_portfolio) x where not exists(select 1 from public.obz_portfolio_targets t where t.target_key=x and t.fiscal_year=2027)) then
  raise exception 'Vínculo contém objetivo, resultado-chave ou meta inexistente';
 end if;
 delete from public.obz_center_strategy_links l where l.center_id=p_center and (
  (l.objective_code is not null and not(l.objective_code=any(v_objectives))) or
  (l.kr_code is not null and not(l.kr_code=any(v_krs))) or
  (l.portfolio_key is not null and not(l.portfolio_key=any(v_portfolio)))
 );
 insert into public.obz_center_strategy_links(center_id,objective_code,created_by)
 select p_center,x,v_actor from unnest(v_objectives) x
 on conflict do nothing;
 insert into public.obz_center_strategy_links(center_id,kr_code,created_by)
 select p_center,x,v_actor from unnest(v_krs) x
 on conflict do nothing;
 insert into public.obz_center_strategy_links(center_id,portfolio_key,created_by)
 select p_center,x,v_actor from unnest(v_portfolio) x
 on conflict do nothing;
 return jsonb_build_object('objectives',cardinality(v_objectives),'krs',cardinality(v_krs),'portfolio_targets',cardinality(v_portfolio));
end; $$;
revoke all on function public.obz_save_center_strategy(uuid,text[],text[],text[]) from public,anon;
grant execute on function public.obz_save_center_strategy(uuid,text[],text[],text[]) to authenticated;