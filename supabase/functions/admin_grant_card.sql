-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.admin_grant_card(p_user uuid, p_card text, p_rarity text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); v_serial bigint;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if public.card_def(p_card) is null or public.rarity_rank(p_rarity) is null then raise exception 'carta inválida' using errcode = 'check_violation'; end if;
  insert into public.cards (user_id, card_id, rarity, origin) values (p_user, p_card, p_rarity, 'admin') returning serial into v_serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_card', p_user, jsonb_build_object('serial', v_serial, 'card', p_card, 'rarity', p_rarity, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
