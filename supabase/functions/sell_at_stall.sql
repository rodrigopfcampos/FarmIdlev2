-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.sell_at_stall(p_item text, p_qty integer, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid(); v_moon numeric := 0;
  fx jsonb; v_price numeric; v_have int; v_amount numeric; v_time double precision; v_boost numeric := 1; v_day date := public.game_day(now());
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'chave de idempotência obrigatória' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.ledger where user_id = v_user and idempotency_key = p_idempotency_key) then
    return public.farm_state(v_user);
  end if;
  v_price := public.item_price(p_item);
  if v_price is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
  if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  fx := public.team_fx(v_user);
  if (fx ->> 'daily_boost')::numeric > 1 and (select boosted_sale_day from public.farms where user_id = v_user) is distinct from v_day then
    v_boost := (fx ->> 'daily_boost')::numeric;
    update public.farms set boosted_sale_day = v_day where user_id = v_user;
  end if;
  update public.silo set qty = qty - p_qty where user_id = v_user and item_id = p_item;
  v_amount := round(p_qty * v_price * (fx ->> 'stall_ratio')::numeric * (1 + (fx ->> 'sales_gold')::numeric) * v_boost, 2);
  v_moon := public.moon_bonus(v_user, v_amount, fx);
  v_amount := v_amount + v_moon;
  perform public.ledger_post(v_user, v_amount, 'stall_sale', jsonb_build_object('item', p_item, 'qty', p_qty, 'price', v_price,
    'ratio', fx -> 'stall_ratio', 'sales_gold', fx -> 'sales_gold', 'boost', v_boost, 'moon', v_moon), p_idempotency_key);
  perform public.mission_progress(v_user, 'stall_gold', v_amount);
  perform public.mission_progress(v_user, 'gold_earned', v_amount);
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots set stalled_reason = null, free_since = v_time where user_id = v_user and stalled_reason = 'sem_ouro';
  perform public.advance_farm(v_user, now());
  perform public.feed_hungry_now(v_user);
  return public.farm_state(v_user);
end;
$function$;
