-- versão atual (veio de supabase/migrations/20261101000100_v3_map_reset.sql)
create or replace function public.admin_reset_farm(p_user uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin');
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.reset_farm(p_user, p_reason);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.reset_farm', p_user, jsonb_build_object('reason', p_reason));
  return public.admin_player_summary(p_user);
end;
$$;
