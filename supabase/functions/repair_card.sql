-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.repair_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; r jsonb := public.config_get('cards') -> 'rarities' -> 'common'; v_cost numeric; v_full numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'worn') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if c.rarity <> 'common' then raise exception 'só a carta Comum tem reparo' using errcode = 'check_violation'; end if;
  v_full := public.card_full_uses('common');
  if coalesce(c.uses_left, v_full) >= v_full then raise exception 'a carta está inteira' using errcode = 'check_violation'; end if;
  v_cost := public.card_repair_cost(v_user);
  perform public.ledger_post(v_user, -v_cost, 'card_repair', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'uses_left', coalesce(c.uses_left, 0)));
  update public.cards set uses_left = least(v_full, coalesce(uses_left, 0) + (r -> 'repair' ->> 'restores_uses')::numeric),
      repairs = repairs + 1, state = case when state = 'worn' then 'binder' else state end, changed_at = now()
    where serial = c.serial;
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;
