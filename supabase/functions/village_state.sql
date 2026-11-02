-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_state(p_user uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare o public.village_orders := public.village_order_current(); last public.village_orders; c jsonb := public.config_get('village') -> 'encomenda'; v_r numeric;
begin
  select * into last from public.village_orders where ends_at <= now() order by ends_at desc limit 1;
  select public.ref_income(level) / 24 into v_r from public.farms where user_id = p_user;
  return jsonb_build_object(
    'order', jsonb_build_object('id', o.id, 'name', o.name_pt, 'items', to_jsonb(o.items), 'goal', o.goal, 'ends_at', o.ends_at, 'players', o.active_players),
    'mine', public.village_result(o.id, p_user),
    'per_unit', (select coalesce(jsonb_object_agg(s.item_id, round(public.item_price(s.item_id) / v_r
        * case when s.item_id = any (o.items) then (c ->> 'requested_bonus')::numeric else 1 end, 4)), '{}')
      from public.silo s where s.user_id = p_user and s.qty > 0 and public.item_price(s.item_id) is not null),
    'gold_per_point', round(v_r, 2),
    'last', case when last.id is null then null else jsonb_build_object('name', last.name_pt, 'result', public.village_result(last.id, p_user),
      'reward', (select to_jsonb(w) - 'user_id' from public.village_rewards w where w.order_id = last.id and w.user_id = p_user)) end,
    'title', public.village_title(p_user),
    'stars', public.star_info(p_user));
end;
$$;
