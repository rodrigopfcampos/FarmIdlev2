-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_revert_ledger(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); l public.ledger;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select * into l from public.ledger where id = p_id;
  if not found then raise exception 'lançamento não encontrado' using errcode = 'check_violation'; end if;
  if l.reason = 'admin_revert' then raise exception 'não dá para reverter uma reversão' using errcode = 'check_violation'; end if;
  perform public.ledger_post(l.user_id, -l.amount, 'admin_revert', jsonb_build_object('reverts', l.id, 'admin', v_admin, 'reason', p_reason), 'revert:' || l.id);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.revert_ledger', l.user_id, jsonb_build_object('ledger', l.id, 'amount', l.amount, 'reason', p_reason));
  return public.admin_player_summary(l.user_id);
end;
$$;
