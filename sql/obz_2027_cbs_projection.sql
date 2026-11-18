insert into public.obz_lines(center_id, source_key, category, description, months)
select c.id, 'OBZ2027:CDL_IA:CBS_LIQUIDA', 'expense', 'CBS LÍQUIDA (DÉBITOS − CRÉDITOS)',
 array_fill(0::numeric,array[12])
from public.obz_centers c
where c.fiscal_year=2027 and c.code='CDL_IA'
 and not exists (select 1 from public.obz_lines l where l.center_id=c.id and l.category='expense' and l.description ilike 'CBS LÍQUIDA%')
on conflict (center_id,source_key) do nothing;

create or replace function public.obz_save_cbs_projection(
 p_center uuid, p_rates jsonb, p_suppliers jsonb, p_note text, p_previous bigint, p_apply boolean
)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
 c public.obz_centers%rowtype;
 v_actor uuid:=auth.uid();
 v_previous bigint;
 v_base numeric[];
 v_debit numeric[];
 v_credit numeric[];
 v_net numeric[];
 v_targets uuid[];
 v_expected integer;
 v_rates jsonb;
 v_value jsonb;
 v_id bigint;
begin
 select * into c from public.obz_centers where id=p_center and fiscal_year=2027 for update;
 if not found or v_actor is null or c.manager_id is distinct from v_actor
    or public.obz_can_manage(p_center) is not true then
  raise exception 'Somente o gestor responsável pode salvar a projeção';
 end if;
 if c.status not in ('draft','changes_requested') then raise exception 'Pacote bloqueado para edição'; end if;

 select id into v_previous from public.obz_audit
 where center_id=p_center and action='cbs_projection' order by id desc limit 1;
 if v_previous is distinct from p_previous then raise exception 'A projeção mudou. Recarregue o pacote antes de salvar.'; end if;

 if p_apply is null or jsonb_typeof(p_rates) is distinct from 'array'
    or jsonb_typeof(p_suppliers) is distinct from 'array'
    or char_length(coalesce(p_note,''))>4000 then raise exception 'Preencha os dados da projeção em formato válido'; end if;

 if jsonb_array_length(p_rates) not between 1 and 200 or jsonb_array_length(p_suppliers)>100 then
  raise exception 'Selecione ao menos uma receita e confira a quantidade de itens';
 end if;

 perform 1 from public.obz_lines where center_id=p_center order by id for update;

 if exists (
  select 1 from jsonb_to_recordset(p_rates) as r(id uuid, rate numeric)
  left join public.obz_lines l on l.id=r.id and l.center_id=p_center and l.category='revenue'
  where l.id is null or r.rate is null or r.rate::text in ('NaN','Infinity','-Infinity')
     or r.rate not between 0 and 100 or r.rate<>round(r.rate,4)
     or array_position(l.months,null) is not null
 ) or (select count(distinct r.id) from jsonb_to_recordset(p_rates) as r(id uuid))<>jsonb_array_length(p_rates) then
  raise exception 'Confira as receitas selecionadas e suas alíquotas (0 a 100%%, até quatro casas decimais)';
 end if;

 if exists (
  select 1 from jsonb_to_recordset(p_suppliers) as s(name text, amounts numeric[])
  where nullif(btrim(s.name),'') is null or char_length(s.name)>200
     or array_ndims(s.amounts) is distinct from 1 or cardinality(s.amounts) is distinct from 12
     or exists (select 1 from unnest(s.amounts) a where a is null or a::text in ('NaN','Infinity','-Infinity')
       or a not between 0 and 999999999999 or a<>round(a,2))
 ) then raise exception 'Identifique cada crédito e informe os 12 valores mensais em reais'; end if;

 select jsonb_agg(jsonb_build_object('id',l.id,'rate',r.rate,'name',l.description,'base',l.months) order by l.id)
 into v_rates
 from jsonb_to_recordset(p_rates) as r(id uuid,rate numeric)
 join public.obz_lines l on l.id=r.id;
 select array_agg(m.base order by i), array_agg(m.debit order by i), array_agg(m.credit order by i),
        array_agg(m.debit-m.credit order by i)
 into v_base,v_debit,v_credit,v_net
 from generate_series(1,12) i
 cross join lateral (
  select coalesce(sum(l.months[i]),0) as base,
         round(coalesce(sum(l.months[i]*r.rate/100),0),2) as debit,
         coalesce((select sum(s.amounts[i]) from jsonb_to_recordset(p_suppliers) as s(amounts numeric[])),0) as credit
  from jsonb_to_recordset(p_rates) as r(id uuid,rate numeric) join public.obz_lines l on l.id=r.id
 ) m;

 if c.code='SPC_BRASIL' then
  select array_agg(id order by source_key desc) into v_targets from public.obz_lines
  where center_id=p_center and category='expense' and source_key in ('OBZ2027:SPC_BRASIL:438','OBZ2027:SPC_BRASIL:431');
  v_expected:=2;
 else
  select array_agg(id order by id) into v_targets from public.obz_lines
  where center_id=p_center and category='expense' and description ilike 'CBS LÍQUIDA%';
  v_expected:=1;
 end if;

 if p_apply then
  if cardinality(v_targets) is distinct from v_expected then raise exception 'O pacote está sem rubrica de CBS vinculada'; end if;
  update public.obz_lines l
  set months=case when v_expected=1 then v_net when l.id=v_targets[1] then v_debit
   else array(select -credit from unnest(v_credit) with ordinality t(credit,n) order by n) end,
   updated_by=v_actor, updated_at=clock_timestamp()
  where l.id=any(v_targets);
 end if;

 v_value:=jsonb_build_object('rates',v_rates,'suppliers',p_suppliers,'note',coalesce(p_note,''),
  'base',v_base,'debit',v_debit,'credit',v_credit,'net',v_net,
  'applied',p_apply,'targets',case when p_apply then v_targets end);
 if exists(select 1 from public.obz_audit where id=v_previous and new_value=v_value) then return v_previous; end if;
 insert into public.obz_audit(center_id,actor_id,action,new_value)
 values(p_center,v_actor,'cbs_projection',v_value) returning id into v_id;
 return v_id;
end;
$$;
revoke all on function public.obz_save_cbs_projection(uuid,jsonb,jsonb,text,bigint,boolean) from public, anon;
grant execute on function public.obz_save_cbs_projection(uuid,jsonb,jsonb,text,bigint,boolean) to authenticated;

create or replace function public.obz_package_snapshot(p_center uuid)
returns jsonb language sql stable set search_path = '' as $$
 select jsonb_build_object(
  'lines', coalesce((
   select jsonb_agg(jsonb_build_object(
    'id', l.id, 'description', l.description, 'category', l.category,
    'months', l.months, 'justification', l.justification,
    'alternative', l.alternative, 'composition_note', l.composition_note,
    'source_key', l.source_key
   ) order by l.description, l.id)
   from public.obz_lines l where l.center_id = p_center
  ), '[]'::jsonb),
  'strategy', coalesce((
   select jsonb_agg(jsonb_build_object(
    'objective_code', s.objective_code, 'kr_code', s.kr_code, 'portfolio_key', s.portfolio_key
   ) order by s.objective_code, s.kr_code, s.portfolio_key)
   from public.obz_center_strategy_links s where s.center_id = p_center
  ), '[]'::jsonb)
 ) || coalesce((
  select jsonb_build_object('cbs',jsonb_build_object('id',a.id,'projection',a.new_value))
  from public.obz_audit a where a.center_id=p_center and a.action='cbs_projection'
  order by a.id desc limit 1
 ), '{}'::jsonb);
$$;
revoke all on function public.obz_package_snapshot(uuid) from public, anon, authenticated;
