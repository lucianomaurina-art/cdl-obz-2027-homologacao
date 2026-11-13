alter table public.obz_lines add column if not exists composition_note text;

create or replace function public.obz_save_composition_note(p_line uuid, p_note text, p_previous_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_center uuid;
  v_status text;
  v_note text;
begin
  if auth.uid() is null then raise exception 'Acesso negado'; end if;
  if char_length(coalesce(p_note,'')) > 4000 then raise exception 'Texto excede limite'; end if;
  select l.center_id, c.status, l.composition_note into v_center, v_status, v_note
    from public.obz_lines l join public.obz_centers c on c.id = l.center_id
    where l.id = p_line for update of l, c;
  if not found or public.obz_can_manage(v_center) is not true then raise exception 'Acesso negado'; end if;
  if v_status not in ('draft','changes_requested') then raise exception 'Pacote bloqueado para edição'; end if;
  if v_note is distinct from p_previous_note then raise exception 'A nota mudou. Recarregue o pacote antes de editar.'; end if;
  update public.obz_lines
    set composition_note = nullif(btrim(p_note),''), updated_by = auth.uid()
    where id = p_line;
end;
$$;
revoke all on function public.obz_save_composition_note(uuid,text,text) from public, anon;
grant execute on function public.obz_save_composition_note(uuid,text,text) to authenticated;
