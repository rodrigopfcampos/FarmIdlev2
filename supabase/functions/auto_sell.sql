-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.auto_sell(p_user uuid, fx jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_total numeric := 0; v_moon numeric := 0; v_items jsonb := '{}'::jsonb; v_price numeric;
begin
  if not coalesce((fx ->> 'auto_sell')::boolean, false) then return 0; end if;
  for r in select item_id, qty from public.silo where user_id = p_user and auto_sell and qty > 0 for update loop
    v_price := public.item_price(r.item_id);
    if v_price is null then continue; end if;
    v_total := v_total + r.qty * v_price * (fx ->> 'stall_ratio')::numeric * (1 + (fx ->> 'sales_gold')::numeric);
    v_items := v_items || jsonb_build_object(r.item_id, r.qty);
    update public.silo set qty = 0 where user_id = p_user and item_id = r.item_id;
  end loop;
  v_total := round(v_total, 2);
  if v_total > 0 then
    v_moon := public.moon_bonus(p_user, v_total, fx);
    v_total := v_total + v_moon;
    perform public.ledger_post(p_user, v_total, 'auto_sale', jsonb_build_object('items', v_items, 'ratio', fx -> 'stall_ratio', 'moon', v_moon));
    perform public.mission_progress(p_user, 'stall_gold', v_total);
    perform public.mission_progress(p_user, 'gold_earned', v_total);
  end if;
  return v_total;
end;
$function$;
