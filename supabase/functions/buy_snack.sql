-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.buy_snack(p_snack text, p_qty int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); s jsonb; v_level int; v_price numeric; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 50 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  s := (select x from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x where x ->> 'id' = p_snack);
  if s is null then raise exception 'lanche não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select level into v_level from public.farms where user_id = v_user;
  fx := public.team_fx(v_user);
  v_price := round(public.ref_income(v_level) * (s ->> 'price_R_ratio')::numeric * (1 - (fx ->> 'shop_discount')::numeric), 2) * p_qty;
  perform public.ledger_post(v_user, -v_price, 'snack', jsonb_build_object('snack', p_snack, 'qty', p_qty));
  insert into public.inventory (user_id, item_id, qty) values (v_user, p_snack, p_qty)
    on conflict (user_id, item_id) do update set qty = public.inventory.qty + p_qty;
  return public.farm_state(v_user);
end;
$$;
