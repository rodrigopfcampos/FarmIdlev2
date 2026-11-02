-- versão atual (veio de supabase/migrations/20261023000600_phase2_click_play.sql)
create or replace function public.admin_grant_gold(p_user uuid, p_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000000 then raise exception 'valor inválido' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.ledger_post(p_user, round(p_amount, 2), 'admin_grant', jsonb_build_object('admin', v_admin, 'reason', p_reason));
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_gold', p_user, jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
