-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.admin_force_payday(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  update public.farms set last_payday = last_payday - 1 where user_id = p_user;
  if not found then raise exception 'fazenda não encontrada' using errcode = 'check_violation'; end if;
  perform public.process_payday(p_user, now());
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.force_payday', p_user, jsonb_build_object('reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
