
-- Additive OBZ 2027 monthly allocations for review scenarios. Does not touch original budget months.
alter table public.obz_line_scenarios
 add column if not exists intermediate_months numeric(16,2)[],
 add column if not exists severe_months numeric(16,2)[];
do $$
begin
 if not exists(select 1 from pg_constraint where conname='obz_scenario_intermediate_months_12') then
  alter table public.obz_line_scenarios add constraint obz_scenario_intermediate_months_12 check(intermediate_months is null or cardinality(intermediate_months)=12);
 end if;
 if not exists(select 1 from pg_constraint where conname='obz_scenario_severe_months_12') then
  alter table public.obz_line_scenarios add constraint obz_scenario_severe_months_12 check(severe_months is null or cardinality(severe_months)=12);
 end if;
end $$;
create or replace function public.obz_save_line_scenario_reviews(p_center uuid,p_reviews jsonb)
returns integer language plpgsql security definer set search_path=public as $$
declare
 item jsonb;
 v_center public.obz_centers%rowtype;
 v_line public.obz_lines%rowtype;
 v_old public.obz_line_scenarios%rowtype;
 v_has_old boolean;
 v_line_id uuid;
 v_count integer:=0;
 v_text text;
 v_alternative text;
 v_ia text; v_sa text; v_ic text; v_sc text;
 v_iv numeric(16,2);v_sv numeric(16,2);
 v_im numeric(16,2)[];v_sm numeric(16,2)[];
 v_changed boolean;
 v_before jsonb;v_after jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória';end if;
 select * into v_center from public.obz_centers where id=p_center and fiscal_year=2027 for update;
 if not found then raise exception 'Pacote inexistente';end if;
 if not public.obz_can_manage(p_center) then raise exception 'Acesso negado';end if;
 if v_center.status not in ('draft','changes_requested') then raise exception 'Pacote bloqueado para revisão de cenários';end if;
 if jsonb_typeof(p_reviews) is distinct from 'array' or jsonb_array_length(p_reviews)<1 or jsonb_array_length(p_reviews)>100 then
  raise exception 'Quantidade ou formato de revisões inválido';
 end if;
 if (select count(distinct x->>'line_id') from jsonb_array_elements(p_reviews) x)<>jsonb_array_length(p_reviews) then
  raise exception 'Rubricas repetidas no mesmo lote';
 end if;
 for item in select value from jsonb_array_elements(p_reviews) loop
   if not (item ? 'line_id' and item ? 'line_updated_at' and item ? 'scenario_updated_at' and item ? 'justification' and item ? 'alternative') then
      raise exception 'Campos obrigatórios da revisão ausentes';
   end if;
   v_line_id:=(item->>'line_id')::uuid;
   select * into v_line from public.obz_lines where id=v_line_id and center_id=p_center for update;
   if not found then raise exception 'Rubrica não pertence ao pacote informado';end if;
   if (item->>'line_updated_at')::timestamptz is distinct from v_line.updated_at then
      raise exception 'Uma rubrica foi alterada em outra sessão. Atualize os dados e revise novamente.';
   end if;
   select * into v_old from public.obz_line_scenarios where line_id=v_line_id for update;
   v_has_old:=found;
   if (item->>'scenario_updated_at')::timestamptz is distinct from (case when v_has_old then v_old.updated_at else null end) then
      raise exception 'Um cenário foi alterado em outra sessão. Atualize os dados e revise novamente.';
   end if;
   v_text:=coalesce(item->>'justification','');
   v_alternative:=coalesce(item->>'alternative','');
   v_ia:=coalesce(btrim(item->>'intermediate_action'),'');
   v_sa:=coalesce(btrim(item->>'severe_action'),'');
   v_ic:=coalesce(item->>'intermediate_consequence','');
   v_sc:=coalesce(item->>'severe_consequence','');
   v_iv:=nullif(btrim(item->>'intermediate_annual'),'')::numeric(16,2);
   v_sv:=nullif(btrim(item->>'severe_annual'),'')::numeric(16,2);
   v_im:=null;v_sm:=null;
   if jsonb_typeof(item->'intermediate_months')='array' then
     select array_agg(value::numeric(16,2) order by ord) into v_im
      from jsonb_array_elements_text(item->'intermediate_months') with ordinality as t(value,ord);
   elsif jsonb_typeof(item->'intermediate_months') not in ('null') then
     raise exception 'Meses intermediários devem ser um conjunto de 12 valores';
   end if;
   if jsonb_typeof(item->'severe_months')='array' then
     select array_agg(value::numeric(16,2) order by ord) into v_sm
      from jsonb_array_elements_text(item->'severe_months') with ordinality as t(value,ord);
   elsif jsonb_typeof(item->'severe_months') not in ('null') then
     raise exception 'Meses severos devem ser um conjunto de 12 valores';
   end if;
   if v_im is not null and (cardinality(v_im)<>12 or array_position(v_im,null) is not null or (select sum(val) from unnest(v_im) as val)::numeric(16,2) is distinct from v_iv) then
     raise exception 'Cenário intermediário: 12 meses devem somar o valor anual informado';
   end if;
   if v_sm is not null and (cardinality(v_sm)<>12 or array_position(v_sm,null) is not null or (select sum(val) from unnest(v_sm) as val)::numeric(16,2) is distinct from v_sv) then
     raise exception 'Cenário severo: 12 meses devem somar o valor anual informado';
   end if;
   if v_ia not in ('','manter','reduzir','ampliar','eliminar','substituir') or v_sa not in ('','manter','reduzir','ampliar','eliminar','substituir') then
      raise exception 'Ação de cenário inválida';
   end if;
   if length(v_text)>4000 or length(v_alternative)>4000 or length(v_ic)>2000 or length(v_sc)>2000 then
      raise exception 'Texto da revisão acima do limite permitido';
   end if;
   if (v_ia='' and (v_iv is not null or v_im is not null)) or (v_sa='' and (v_sv is not null or v_sm is not null)) then
      raise exception 'Escolha a ação do cenário antes de informar seus valores';
   end if;
   if (v_ia='eliminar' and v_iv is not null and v_iv<>0) or (v_sa='eliminar' and v_sv is not null and v_sv<>0) then
      raise exception 'Para eliminar uma rubrica o valor proposto deve ser zero';
   end if;
   v_changed:=false;
   if v_line.justification is distinct from v_text or v_line.alternative is distinct from v_alternative then
      update public.obz_lines set justification=v_text,alternative=v_alternative,
       updated_by=auth.uid(),updated_at=now() where id=v_line_id;
      v_changed:=true;
   end if;
   v_after:=jsonb_build_object('intermediate_action',v_ia,'intermediate_annual',v_iv,
     'intermediate_months',v_im,'intermediate_consequence',v_ic,'severe_action',v_sa,
     'severe_annual',v_sv,'severe_months',v_sm,'severe_consequence',v_sc);
   if not v_has_old then
      if v_ia<>'' or v_iv is not null or v_im is not null or v_ic<>'' or v_sa<>'' or v_sv is not null or v_sm is not null or v_sc<>'' then
         insert into public.obz_line_scenarios(line_id,center_id,intermediate_action,intermediate_annual,
           intermediate_months,intermediate_consequence,severe_action,severe_annual,severe_months,severe_consequence,updated_by)
         values(v_line_id,p_center,v_ia,v_iv,v_im,v_ic,v_sa,v_sv,v_sm,v_sc,auth.uid());
         insert into public.obz_audit(center_id,line_id,actor_id,action,new_value)
          values(p_center,v_line_id,auth.uid(),'scenario_review',v_after);
         v_changed:=true;
      end if;
   else
      v_before:=jsonb_build_object('intermediate_action',v_old.intermediate_action,
         'intermediate_annual',v_old.intermediate_annual,'intermediate_months',v_old.intermediate_months,
         'intermediate_consequence',v_old.intermediate_consequence,'severe_action',v_old.severe_action,
         'severe_annual',v_old.severe_annual,'severe_months',v_old.severe_months,
         'severe_consequence',v_old.severe_consequence);
      if v_before is distinct from v_after then
       update public.obz_line_scenarios set intermediate_action=v_ia,intermediate_annual=v_iv,
         intermediate_months=v_im,intermediate_consequence=v_ic,severe_action=v_sa,severe_annual=v_sv,
         severe_months=v_sm,severe_consequence=v_sc,updated_by=auth.uid(),updated_at=now()
         where line_id=v_line_id;
       insert into public.obz_audit(center_id,line_id,actor_id,action,old_value,new_value)
          values(p_center,v_line_id,auth.uid(),'scenario_review',v_before,v_after);
       v_changed:=true;
      end if;
   end if;
   if v_changed then v_count:=v_count+1;end if;
 end loop;
 return v_count;
end;$$;
revoke all on function public.obz_save_line_scenario_reviews(uuid,jsonb) from public,anon;
grant execute on function public.obz_save_line_scenario_reviews(uuid,jsonb) to authenticated;
