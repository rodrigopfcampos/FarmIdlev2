-- versão atual (veio de supabase/migrations/20261023000600_phase2_click_play.sql)
create or replace function public.admin_set_level(p_user uuid, p_level int, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_from int;
begin
  if p_level is null or p_level < 1 or p_level > 50 then raise exception 'nível inválido' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select level into v_from from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada' using errcode = 'check_violation'; end if;
  update public.farms set level = p_level, xp = 0 where user_id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.set_level', p_user, jsonb_build_object('from', v_from, 'to', p_level, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
