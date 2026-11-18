-- Read-only feed for the Google Sheets worker. Store a unique, random
-- integration token as obz_sheets_sync_token in Supabase Vault.
create or replace function public.obz_sheet_changes(p_after bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 expected text;
 supplied text;
begin
 select decrypted_secret into expected from vault.decrypted_secrets where name='obz_sheets_sync_token';
 supplied:=coalesce(current_setting('request.headers',true),'{}')::jsonb->>'x-obz-sync-token';
 if expected is null or length(expected)<32 or supplied is null
    or extensions.digest(supplied,'sha256')<>extensions.digest(expected,'sha256') then
  raise sqlstate 'PT403' using message='Acesso negado à sincronização do OBZ';
 end if;
 -- Serialize with monthly audit writes so the cursor cannot skip a transaction
 -- that committed after a larger event ID.
 perform pg_advisory_xact_lock(2027,587542658);
 if p_after is null then
  return jsonb_build_object('cursor',coalesce((select max(id) from public.obz_audit where action='UPDATE' and old_value->'months' is distinct from new_value->'months'),0)::text);
 end if;
 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'id',q.id::text,'saved_at',q.created_at,'source_key',q.new_value->>'source_key',
   'description',q.new_value->>'description','category',q.new_value->>'category',
   'account',q.new_value->>'account_code','previous',q.old_value->'months','months',q.new_value->'months'
  ) order by q.id)
  from (
   select a.id,a.created_at,a.old_value,a.new_value from public.obz_audit a
   join public.obz_centers c on c.id=a.center_id
   where a.id>p_after and a.action='UPDATE' and c.fiscal_year=2027
    and a.old_value->'months' is distinct from a.new_value->'months'
   order by a.id limit 50
  ) q
 ),'[]'::jsonb);
end;
$$;
revoke all on function public.obz_sheet_changes(bigint) from public, authenticated;
grant execute on function public.obz_sheet_changes(bigint) to anon;

create or replace function public.obz_audit_line()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.months is distinct from old.months then
  perform pg_advisory_xact_lock(2027,587542658);
 end if;
 insert into public.obz_audit(center_id,line_id,actor_id,action,old_value,new_value)
 values(new.center_id,new.id,auth.uid(),tg_op,to_jsonb(old),to_jsonb(new));
 return new;
end;
$$;
