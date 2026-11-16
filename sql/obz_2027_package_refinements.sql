-- Preserve each completed refinement in the existing, access-controlled audit log.
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
 );
$$;
revoke all on function public.obz_package_snapshot(uuid) from public, anon, authenticated;

create or replace function public.obz_complete_refinement(
 p_center uuid, p_conclusion text, p_previous bigint
)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
 c public.obz_centers%rowtype;
 previous public.obz_audit%rowtype;
 snapshot jsonb;
 conclusion text := nullif(btrim(p_conclusion), '');
 cycle bigint;
 saved_id bigint;
begin
 select * into c from public.obz_centers where id = p_center for update;
 if not found or auth.uid() is null or c.manager_id is distinct from auth.uid()
    or not public.obz_can_manage(p_center) then
  raise exception 'Somente o responsável designado pode concluir o refinamento';
 end if;
 if c.status not in ('draft', 'changes_requested') then
  raise exception 'Pacote bloqueado para refinamento';
 end if;
 if conclusion is null or length(conclusion) > 6000 then
  raise exception 'Preencha a conclusão do gestor com até 6.000 caracteres';
 end if;

 perform 1 from public.obz_lines where center_id = p_center order by id for share;
 snapshot := public.obz_package_snapshot(p_center);
 if jsonb_array_length(snapshot->'lines') = 0 or exists (
  select 1 from jsonb_array_elements(snapshot->'lines') l
  where nullif(btrim(l->>'justification'), '') is null
 ) then
  raise exception 'Salve as justificativas de todas as rubricas antes de concluir';
 end if;

 select coalesce(max(id), 0) into cycle from public.obz_audit
 where center_id = p_center and action = 'status' and new_value->>'status' = 'changes_requested';
 select * into previous from public.obz_audit
 where center_id = p_center and action = 'package_refinement' order by id desc limit 1;
 if previous.new_value = jsonb_build_object(
  'snapshot', snapshot, 'conclusion', conclusion, 'cycle', cycle
 ) then
  return previous.id;
 end if;
 if previous.id is distinct from p_previous then
  raise exception 'O histórico foi atualizado. Recarregue o pacote e confira a última rodada';
 end if;
 insert into public.obz_audit(center_id, actor_id, action, new_value)
 values(p_center, auth.uid(), 'package_refinement',
  jsonb_build_object('snapshot', snapshot, 'conclusion', conclusion, 'cycle', cycle))
 returning id into saved_id;
 return saved_id;
end;
$$;
revoke all on function public.obz_complete_refinement(uuid,text,bigint) from public, anon;
grant execute on function public.obz_complete_refinement(uuid,text,bigint) to authenticated;

-- Keep the existing transition and record the exact refinement sent to Governance.
create or replace function public.obz_change_status(p_center uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare
 c public.obz_centers%rowtype;
 v_admin boolean;
 v_missing integer;
 v_refinement public.obz_audit%rowtype;
 v_cycle bigint;
begin
 select * into c from public.obz_centers where id=p_center for update;
 if not found then raise exception 'Pacote inexistente'; end if;
 if auth.uid() is null or not public.obz_can_manage(p_center) then raise exception 'Acesso negado'; end if;
 v_admin:=public.obz_is_admin();
 if not (
  (c.status in ('draft','changes_requested') and p_status='submitted'
   and (c.manager_id=auth.uid()))
  or
  (v_admin and
    ((c.status='submitted' and p_status in ('in_review','changes_requested','approved'))
     or (c.status='in_review' and p_status in ('changes_requested','approved'))
     or (c.status='approved' and p_status='changes_requested')
     or (c.status='changes_requested' and p_status='draft')))
 ) then
  raise exception 'Transição de status não permitida';
 end if;
 if v_admin and c.manager_id=auth.uid() and p_status in ('in_review','changes_requested','approved') then
  raise exception 'Segregação de alçadas: não é permitido revisar ou aprovar o próprio pacote';
 end if;
 if p_status='submitted' then
  perform 1 from public.obz_lines where center_id=p_center order by id for share;
  select coalesce(max(id),0) into v_cycle from public.obz_audit
   where center_id=p_center and action='status' and new_value->>'status'='changes_requested';
  select * into v_refinement from public.obz_audit
   where center_id=p_center and action='package_refinement' order by id desc limit 1;
  if v_refinement.id is null
     or (v_refinement.new_value->>'cycle')::bigint is distinct from v_cycle
     or v_refinement.new_value->'snapshot' is distinct from public.obz_package_snapshot(p_center) then
   raise exception 'Conclua o refinamento com a análise e os vínculos atuais antes de submeter';
  end if;
 end if;
 if p_status in ('submitted','approved') then
  if not exists(select 1 from public.obz_lines where center_id=p_center) then
   raise exception 'Pacote sem rubricas não pode ser submetido ou aprovado';
  end if;
  select count(*) into v_missing from public.obz_lines
   where center_id=p_center and nullif(btrim(coalesce(justification,'')),'') is null;
  if v_missing>0 then
   raise exception 'Análise incompleta: % rubrica(s) sem justificativa técnica',v_missing;
  end if;
  if not exists(select 1 from public.obz_center_strategy_links
   where center_id=p_center and kr_code is not null) then
   raise exception 'Vincule e salve ao menos um resultado-chave (RK) antes da submissão/aprovação';
  end if;
 end if;
 update public.obz_centers set status=p_status,updated_at=now() where id=p_center;
 insert into public.obz_audit(center_id,actor_id,action,old_value,new_value)
 values(p_center,auth.uid(),'status',jsonb_build_object('status',c.status),jsonb_strip_nulls(jsonb_build_object('status',p_status,'refinement_id',v_refinement.id)));
end; $$;
revoke all on function public.obz_change_status(uuid,text) from public,anon;
grant execute on function public.obz_change_status(uuid,text) to authenticated;
