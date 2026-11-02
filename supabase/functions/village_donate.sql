-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_donate(p_item text, p_qty numeric)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); c jsonb := public.config_get('village') -> 'encomenda'; o public.village_orders; v_have int; v_value numeric; v_pts numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  o := public.village_order_current();
  if p_item is null then
    v_value := round(p_qty, 2);
    perform public.ledger_post(v_user, -v_value, 'village_donation', jsonb_build_object('order', o.id));
    v_pts := public.village_points(v_user, v_value);
  else
    if p_qty <> floor(p_qty) then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
    if public.item_price(p_item) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
    select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
    if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
    update public.silo set qty = qty - p_qty::int where user_id = v_user and item_id = p_item;
    v_value := round(p_qty * public.item_price(p_item), 2);
    v_pts := public.village_points(v_user, v_value) * case when p_item = any (o.items) then (c ->> 'requested_bonus')::numeric else 1 end;
  end if;
  insert into public.village_donations (order_id, user_id, item_id, qty, value, points) values (o.id, v_user, p_item, p_qty, v_value, round(v_pts, 4));
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'village.donate', v_user, jsonb_build_object('order', o.id, 'item', p_item, 'qty', p_qty, 'value', v_value, 'points', round(v_pts, 4)));
  return public.village_state(v_user);
end;
$$;
