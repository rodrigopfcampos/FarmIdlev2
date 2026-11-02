-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.exp_depart(p_user uuid, p_convoy uuid, v vehicles, p_route text, p_cargo jsonb, p_insured boolean, p_lead jsonb, p_minigame text, p_t double precision, p_seq integer, p_repeat_left integer, fx jsonb, p_gold_left numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e jsonb := public.config_get('expeditions'); r jsonb := public.exp_route(p_route);
  v_day date := public.game_day(now()); v_value numeric; v_ins numeric := 0; v_dem jsonb;
begin
  v_value := public.exp_cargo_value(p_cargo, p_route, v_day);
  select coalesce(jsonb_agg(k), '[]') into v_dem from jsonb_object_keys(p_cargo) k where k = any (public.demand_of(v_day, p_route));
  if p_insured and r ->> 'insurance_pct' is not null then
    v_ins := round(v_value * (r ->> 'insurance_pct')::numeric / 100 * (1 + coalesce((p_lead ->> 'insurance_pct')::numeric, 0) / 100), 2);
    if v_ins > coalesce(p_gold_left, 0) then v_ins := 0; end if;  -- repetição sem ouro sai sem seguro
  end if;
  insert into public.expeditions (user_id, convoy_id, vehicle_id, route_id, cargo, cargo_value, demand, insurance, led, minigame, chance,
      started_at, returns_at, seq, repeat_left, card_fx)
    values (p_user, p_convoy, v.vehicle_id, p_route, p_cargo, v_value, v_dem, v_ins, p_lead is not null, p_minigame,
      public.exp_chance(p_user, v, p_route, p_lead, p_minigame, fx), p_t, p_t + public.exp_hours(v, p_route, p_lead, fx) * 3600, p_seq, p_repeat_left,
      coalesce(fx -> 'exp_card', '{}'));
  perform public.mission_progress(p_user, 'expeditions_sent', 1);
  update public.vehicles set durability = greatest(0, durability - (e ->> 'wear_per_trip_pct')::double precision * (1 + coalesce((fx ->> 'vehicle_wear')::double precision, 0)))
    where user_id = p_user and vehicle_id = v.vehicle_id;
  if v_ins > 0 then
    perform public.ledger_post(p_user, -v_ins, 'exp_insurance', jsonb_build_object('convoy', p_convoy, 'vehicle', v.vehicle_id, 'route', p_route, 'seq', p_seq));
  end if;
  return v_ins;
end;
$function$;
