-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_config_restore(p_name text, p_version int, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); v_new int; v_data jsonb;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select data into v_data from public.game_config where name = p_name and version = p_version;
  if v_data is null then raise exception 'versão não encontrada' using errcode = 'check_violation'; end if;
  select max(version) + 1 into v_new from public.game_config where name = p_name;
  insert into public.game_config (name, version, data) values (p_name, v_new, v_data || jsonb_build_object('version', v_new, 'restored_from', p_version));
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.config_restore', jsonb_build_object('name', p_name, 'from', p_version, 'to', v_new, 'reason', p_reason));
  return public.admin_config_versions(p_name);
end;
$$;
