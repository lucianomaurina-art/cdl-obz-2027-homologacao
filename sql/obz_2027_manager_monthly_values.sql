-- The manager may update the values of an assigned package during refinement.
-- Keep the existing admin-only update policy and expose a scoped RPC.
create or replace function public.obz_guard_financial_changes()
returns trigger language plpgsql set search_path = '' as $$
declare
 v_status text;
 v_manager uuid;
begin
 select status, manager_id into v_status, v_manager
 from public.obz_centers where id=new.center_id;

 if v_status='approved' then
  raise exception 'Pacote aprovado: reabra o pacote antes de alterar rubricas';
 end if;
 if not public.obz_is_admin() then
  if new.category is distinct from old.category
     or new.center_id is distinct from old.center_id
     or new.source_key is distinct from old.source_key then
   raise exception 'Somente administrador pode alterar a vinculação da rubrica';
  end if;
  if new.months is distinct from old.months and (
     auth.uid() is null or v_manager is distinct from auth.uid()
     or v_status not in ('draft','changes_requested')
     or public.obz_can_manage(new.center_id) is not true
  ) then
   raise exception 'Somente o gestor responsável pode alterar valores durante o refinamento';
  end if;
 end if;
 return new;
end;
$$;

create or replace function public.obz_save_rubric_analysis(
 p_center uuid, p_line uuid, p_months numeric[],
 p_justification text, p_alternative text, p_previous_updated_at timestamptz
)
returns void language plpgsql security definer set search_path = '' as $$
declare
 v_actor uuid := auth.uid();
 v_center public.obz_centers%rowtype;
 v_line public.obz_lines%rowtype;
begin
 if v_actor is null or public.obz_can_manage(p_center) is not true then
  raise exception 'Acesso negado ao pacote';
 end if;

 select * into v_center from public.obz_centers
 where id=p_center and fiscal_year=2027 for update;
 if not found or (
  not public.obz_is_admin() and (
   v_center.manager_id is distinct from v_actor or public.obz_can_manage(p_center) is not true
  )
 ) then
  raise exception 'Acesso negado ao pacote';
 end if;
 if v_center.status='approved' or (
  not public.obz_is_admin() and v_center.status not in ('draft','changes_requested')
 ) then
  raise exception 'Pacote bloqueado para edição';
 end if;

 select * into v_line from public.obz_lines where id=p_line and center_id=p_center for update;
 if not found then raise exception 'Rubrica inexistente neste pacote'; end if;
 if v_line.updated_at is distinct from p_previous_updated_at then
  raise exception 'A análise foi alterada. Recarregue o pacote e confira os valores antes de salvar.';
 end if;
 if array_ndims(p_months) is distinct from 1 or cardinality(p_months) is distinct from 12
    or exists(select 1 from unnest(p_months) as value
      where value is null or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2)) then
  raise exception 'Informe os 12 valores mensais com até duas casas decimais';
 end if;
 if nullif(btrim(p_justification),'') is null
    or char_length(p_justification)>4000 or char_length(coalesce(p_alternative,''))>4000 then
  raise exception 'Preencha a justificativa e respeite o limite de 4.000 caracteres por campo';
 end if;

 update public.obz_lines
 set months=p_months, justification=btrim(p_justification), alternative=coalesce(p_alternative,''),
     updated_by=v_actor, updated_at=clock_timestamp()
 where id=p_line;
end;
$$;
revoke all on function public.obz_save_rubric_analysis(uuid,uuid,numeric[],text,text,timestamptz) from public, anon;
grant execute on function public.obz_save_rubric_analysis(uuid,uuid,numeric[],text,text,timestamptz) to authenticated;
