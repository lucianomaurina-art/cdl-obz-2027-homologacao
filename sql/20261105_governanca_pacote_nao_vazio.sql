-- OBZ 2027 — proteção de governança no banco.
-- Executar após as três migrações iniciais. Não altera dados financeiros existentes.
-- Rejeita submissão/aprovação de pacotes vazios mesmo quando a chamada ignora a interface.
begin;
create or replace function public.obz_change_status(p_center uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare c public.obz_centers%rowtype; v_admin boolean;
begin
 select * into c from public.obz_centers where id=p_center for update;
 if not found then raise exception 'Pacote inexistente'; end if;
 v_admin:=public.obz_is_admin();
 if not public.obz_can_manage(p_center) then raise exception 'Acesso negado'; end if;
 if not ((not v_admin and c.status in ('draft','changes_requested') and p_status='submitted')
 or (v_admin and ((c.status='submitted' and p_status in ('in_review','changes_requested','approved'))
 or (c.status='in_review' and p_status in ('changes_requested','approved'))
 or (c.status='approved' and p_status='changes_requested')
 or (c.status='changes_requested' and p_status='draft')))) then
 raise exception 'Transição de status não permitida';
 end if;
 if p_status in ('submitted','approved') and not exists (
   select 1 from public.obz_lines where center_id=p_center
 ) then
   raise exception 'Pacote sem rubricas não pode ser submetido ou aprovado';
 end if;
 update public.obz_centers set status=p_status,updated_at=now() where id=p_center;
 insert into public.obz_audit(center_id,actor_id,action,old_value,new_value)
 values(p_center,auth.uid(),'status',jsonb_build_object('status',c.status),jsonb_build_object('status',p_status));
end; $$;
revoke all on function public.obz_change_status(uuid,text) from public,anon;
grant execute on function public.obz_change_status(uuid,text) to authenticated;
commit;
