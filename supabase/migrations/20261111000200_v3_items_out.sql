-- Gerada por "npm run db:migration" a partir de supabase/functions/ (mudam: char_energy, char_rate, farm_state, lead_info, team_fx, tick_team; saem: equip_def, item_effect).

create or replace function public.char_energy(c characters, fx jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + coalesce((fx ->> 'acct_max_energy')::double precision, 0),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'absolute')::double precision, 100) / 100,
             (1 - coalesce((fx ->> 'card_use_cut')::double precision, 0)) * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + (public.skill_effect(c.class_id, c.skills, 'energy_use_pct') + coalesce((fx ->> 'acct_energy_use')::double precision, 0)) / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * case when c.energy < (ch -> 'energy' ->> 'low_energy_fraction')::double precision * ((ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + coalesce((fx ->> 'acct_max_energy')::double precision, 0))
                                  then 1 + coalesce((fx ->> 'low_energy_use')::double precision, 0) else 1 end
                           )),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'absolute')::double precision, 200) / 100,
             coalesce((fx ->> 'card_rest_buff')::double precision, 0) + least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + (public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') + coalesce((fx ->> 'acct_rest')::double precision, 0)) / 100) * (1 + coalesce((fx ->> 'card_rest_perm')::double precision, 0)))))
  from cfg
$function$;

CREATE OR REPLACE FUNCTION public.char_rate(c characters, p_material text, p_durability double precision, fx jsonb)
 RETURNS double precision
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (select public.config_get('characters') ch, public.config_get('tools_and_items') -> 'tool_durability_rules' dr)
  select (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision
       * (public.material_def(p_material) ->> 'work_capacity_multiplier')::double precision * (1 + (fx ->> 'tool_effect')::double precision)
       * case when p_durability < (dr ->> 'low_durability_threshold')::double precision then (dr ->> 'low_durability_capacity_penalty_multiplier')::double precision else 1 end
       * coalesce((ch -> 'role_efficiency' ->> (public.class_def(c.class_id) ->> 'role'))::double precision, (ch -> 'role_efficiency' ->> 'other')::double precision)
       * (1 + public.skill_effect(c.class_id, c.skills, 'work_capacity_pct') / 100 + (fx ->> 'team_capacity')::double precision)
       * case when c.debt > 0 then (ch -> 'salary' ->> 'unpaid_efficiency')::double precision else 1 end
  from cfg
$function$;

create or replace function public.farm_state(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  fx jsonb := public.team_fx(p_user);
  tr jsonb := public.team_rate(p_user, fx);
  v_level int; base jsonb; v_chars jsonb; v_snacks jsonb;
begin
  select level into v_level from public.farms where user_id = p_user;
  select coalesce(jsonb_agg(jsonb_build_object(
      'class_id', ch.class_id, 'slot', ch.slot, 'energy', round(ch.energy::numeric, 2), 'parked', ch.parked,
      'level', ch.level, 'work_hours', round(ch.work_hours::numeric, 3), 'skills', ch.skills, 'skill_choice', ch.skill_choice,
      'reset_week', ch.reset_week, 'debt', ch.debt, 'unpaid_days', ch.unpaid_days, 'snack_id', ch.snack_id, 'snack_qty', ch.snack_qty,
      'material', coalesce(t.material, 'wood'), 'durability', round(coalesce(t.durability, 100)::numeric, 2),
      'rate', round(public.char_rate(ch, t.material, coalesce(t.durability, 100), fx)::numeric, 3),
      'energy_max', (public.char_energy(ch, fx) ->> 'max')::numeric, 'energy_use', round((public.char_energy(ch, fx) ->> 'use')::numeric, 3),
      'energy_rest', round((public.char_energy(ch, fx) ->> 'rest')::numeric, 3), 'active', public.char_active(ch), 'leading', ch.leading_id is not null,
      'salary', public.salary_of(p_user, ch)) order by ch.hired_at), '[]')
    into v_chars
    from public.characters ch left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
    where ch.user_id = p_user;
  select coalesce(jsonb_object_agg(x ->> 'id', round(public.ref_income(v_level) * (x ->> 'price_R_ratio')::numeric * (1 - (fx ->> 'shop_discount')::numeric), 2)), '{}')
    into v_snacks from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x;
  select jsonb_build_object(
    'server_now', now(),
    'game_day', public.user_day(p_user, now()),
    'weather', public.weather_view(p_user, fx),
    'farm_time', f.farm_time,
    'synced_at', f.synced_at,
    'last_activity_at', f.last_activity_at,
    'offline_cap_hours', (public.config_get('farm') ->> 'offline_cap_hours')::int,
    'labor_bank', f.labor_bank,
    'labor_per_hour', round((tr ->> 'working')::numeric, 3),
    'labor_nominal', round((tr ->> 'nominal')::numeric, 3),
    'labor_cap_hours', (public.config_get('farm') ->> 'labor_bank_cap_hours')::double precision,
    'nickname', pr.nickname,
    'is_admin', pr.is_admin,
    'gold', w.gold,
    'level', f.level,
    'xp', f.xp,
    'xp_to_next', (public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric,
    'last_payday', f.last_payday,
    'boosted_sale_day', f.boosted_sale_day,
    'pet_swapped_at', f.pet_swapped_at,
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', l.lot_id, 'ready_at', l.ready_at, 'purchase_n', l.purchase_n) order by l.lot_id), '[]')
      from public.owned_lots l where l.user_id = p_user),
    'plots', (select coalesce(jsonb_agg(jsonb_build_object(
        'plot_id', pl.plot_id, 'crop_id', pl.crop_id, 'state', pl.state, 'planted_crop_id', pl.planted_crop_id,
        'planted_at', pl.planted_at, 'ready_at', pl.ready_at, 'harvests_done', pl.harvests_done, 'stalled_reason', pl.stalled_reason,
        'rarity', pl.rarity) order by pl.plot_id), '[]')
      from public.plots pl where pl.user_id = p_user),
    'trees', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', t.lot_id, 'slot', t.slot, 'fruit_id', t.fruit_id,
        'planted_at', t.planted_at, 'ready_at', t.ready_at, 'rarity', t.rarity, 'rare_left', t.rare_left) order by t.lot_id, t.slot), '[]')
      from public.trees t where t.user_id = p_user),
    'silo', (select coalesce(jsonb_object_agg(s.item_id, s.qty), '{}') from public.silo s where s.user_id = p_user and s.qty > 0),
    'auto_sell', (select coalesce(jsonb_agg(s.item_id order by s.item_id), '[]') from public.silo s where s.user_id = p_user and s.auto_sell),
    'inventory', (select coalesce(jsonb_object_agg(iv.item_id, iv.qty), '{}') from public.inventory iv where iv.user_id = p_user and iv.qty > 0),
    'tools', (select coalesce(jsonb_object_agg(tl.class_id, tl.material), '{}') from public.tools tl where tl.user_id = p_user),
    'characters', v_chars,
    'animals', (select coalesce(jsonb_agg(jsonb_build_object('house_id', a.house_id, 'slot', a.slot, 'animal_id', a.animal_id, 'rarity', a.rarity,
        'state', a.state, 'cycle_start', a.cycle_start, 'ready_at', a.ready_at) order by a.house_id, a.slot), '[]')
      from public.animals a where a.user_id = p_user),
    'houses', (select jsonb_object_agg(h.key, jsonb_build_object('owned', public.house_ready(p_user, h.key, f.farm_time),
        'tier', coalesce((select ah.tier from public.animal_houses ah where ah.user_id = p_user and ah.house_id = h.key), 0),
        'slots', public.house_slots(p_user, h.key), 'bird_slots', public.house_bird_slots(p_user, h.key, f.farm_time), 'lot', public.house_lot(h.key)))
      from jsonb_each(public.config_get('animals') -> 'houses') h),
    'lake', public.lake_ready(p_user, f.farm_time),
    'fishing', public.fish_state(p_user),
    'account_tree', public.account_tree_state(p_user),
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p.pet_id, 'affinity', p.affinity, 'last_care', p.last_care,
        'level', public.pet_level(p_user, p.pet_id), 'find_t', p.find_t) order by p.adopted_at), '[]') from public.pets p where p.user_id = p_user),
    'pet', fx -> 'pet',
    'snack_prices', v_snacks,
    'fx', jsonb_build_object('stall_ratio', fx -> 'stall_ratio', 'seed_discount', fx -> 'seed_discount', 'sales_gold', fx -> 'sales_gold',
        'shop_discount', fx -> 'shop_discount', 'auto_sell', fx -> 'auto_sell', 'auto_pay', fx -> 'auto_pay', 'rare_seed', fx -> 'rare_seed',
        'seed_refund', fx -> 'seed_refund', 'gerente_cut', fx -> 'gerente_cut', 'early_unlock', fx -> 'early_unlock', 'daily_boost', fx -> 'daily_boost',
        'growth_crop', fx -> 'growth_crop', 'growth_orchard', fx -> 'growth_orchard', 'tree_initial', fx -> 'tree_initial', 'cleanup', fx -> 'cleanup',
        'tool_cost', fx -> 'tool_cost', 'harvest_xp', fx -> 'harvest_xp', 'golden', fx -> 'golden',
        'feed_discount', fx -> 'feed_discount', 'animal_production', fx -> 'animal_production', 'animal_cap', fx -> 'animal_cap',
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira',
        'exp_success', fx -> 'exp_success', 'exp_duration', fx -> 'exp_duration', 'vehicle_wear', fx -> 'vehicle_wear', 'dog_recover', fx -> 'dog_recover',
        'char_xp', fx -> 'char_xp', 'account_xp', fx -> 'account_xp')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base || public.exp_state(p_user) || public.cards_state(p_user) || public.social_badge(p_user);
end;
$function$;

create or replace function public.lead_info(p_user uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'available', g.leading_id is null and g.unpaid_days < coalesce((public.config_get('characters') -> 'salary' ->> 'stops_after_days')::int, 3),
    'leading', g.leading_id is not null,
    'vehicles', coalesce((public.config_get('expeditions') -> 'manager' ->> 'vehicles_led')::int, 1) + public.skill_effect('gerente', g.skills, 'lead_two_vehicles')::int,
    'success_pts', (public.config_get('expeditions') -> 'manager' ->> 'success_pts')::double precision
                   + public.skill_effect('gerente', g.skills, 'lead_success_pts'),
    'duration_mult', (public.config_get('expeditions') -> 'manager' ->> 'duration_multiplier')::double precision
                     * (1 + public.skill_effect('gerente', g.skills, 'lead_duration_pct') / 100),
    'capacity_pct', public.skill_effect('gerente', g.skills, 'lead_capacity_pct'),
    'loss_pct', public.skill_effect('gerente', g.skills, 'failure_loss_pct'),
    'insurance_pct', public.skill_effect('gerente', g.skills, 'insurance_cost_pct'),
    'item_pct', public.skill_effect('gerente', g.skills, 'item_chance_pct'),
    'deed_pct', public.skill_effect('gerente', g.skills, 'deed_chance_pct'),
    'crit_pts', public.skill_effect('gerente', g.skills, 'crit_chance_pts'),
    'extra_seconds', (public.config_get('expeditions') -> 'minigame' ->> 'manager_extra_seconds')::double precision)
  from public.characters g where g.user_id = p_user and g.class_id = 'gerente'
$$;

create or replace function public.team_fx(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := public.config_get('characters');
  fe jsonb := cfg -> 'field_effects';
  crops jsonb := public.config_get('crops') -> 'rules';
  base_stall double precision := coalesce((public.config_get('expeditions') ->> 'stall_price_ratio')::double precision, 0.7);
  v_effects text[] := array['crop_growth_pct', 'growth_all_pct', 'orchard_speed_pct', 'tree_initial_time_pct', 'double_harvest_crop_pct',
    'golden_pct', 'harvest_xp_pct', 'seed_cost_pct', 'shop_discount_pct', 'cleanup_time_pct', 'tool_cost_pct', 'team_capacity_pct',
    'tool_effect_pct', 'stall_price_pts', 'daily_boosted_sale', 'sales_gold_pct', 'recurring_production_pct', 'account_xp_pct',
    'orchard_extra_fruit_chance', 'early_unlock_levels', 'animal_production_pct', 'feed_cost_pct', 'animal_double_pct',
    'expansion_cost_pct', 'vehicle_wear_pct', 'expedition_success_pts', 'expedition_duration_pct', 'route_demand_preview',
    'weather_effect_pct', 'weather_forecast_hours', 'night_event_pct'];
  caps jsonb := coalesce(public.config_get('cards') -> 'bonus_caps', '{}'::jsonb);
  cap_seed double precision := coalesce((caps -> 'seed_sapling_feed_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100;
  ranch boolean := false;
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0; gato_animal double precision := 0;
  cf jsonb := public.card_fx(p_user, public.fx_at()); cb jsonb; ca jsonb; v_storm double precision;
  v_res jsonb; v_w jsonb := public.weather_now(p_user, public.fx_at()); wcfg jsonb := public.config_get('weather');
  wm double precision; em double precision; cw jsonb; ew jsonb; v_base double precision; v_room double precision; v_cg double precision;
  v_go double precision; v_xp double precision; v_cxp double precision; v_sales double precision; v_warn int;
  dog_pts double precision := 0; dog_rec double precision := 0;
begin
  cb := cf -> 'buff'; ca := cf -> 'armory';
  foreach e in array v_effects loop s := s || jsonb_build_object(e, 0); end loop;
  for c in select ch.class_id, ch.skills, ch.skill_choice, t.material from public.characters ch
           left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
           where ch.user_id = p_user and public.char_active(ch) loop
    foreach e in array v_effects loop
      v := public.skill_effect(c.class_id, c.skills, e);
      if v <> 0 then s := jsonb_set(s, array[e], to_jsonb((s ->> e)::double precision + v)); end if;
    end loop;
    if c.class_id = 'comerciante' then com := public.material_idx(c.material); end if;
    if c.class_id = 'gerente' then ger := public.material_idx(c.material); end if;
    if c.class_id = 'botanica' then bot := true; bot_choice := c.skill_choice; end if;
    if c.class_id = 'rancheira' then ranch := true; end if;
  end loop;
  -- árvore da conta (R3): soma por cima do que vem dos personagens
  foreach e in array v_effects loop
    v := public.account_skill(p_user, e);
    if v <> 0 then s := jsonb_set(s, array[e], to_jsonb((s ->> e)::double precision + v)); end if;
  end loop;
  -- pets (v3): os três valem ao mesmo tempo, cada um pelo próprio nível
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    gato := coalesce((public.pet_def('gato') ->> 'energy_recovery_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'gato');
    gato_animal := coalesce((public.pet_def('gato') ->> 'animal_production_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'gato');
    dog_pts := coalesce((public.pet_def('cachorro') ->> 'expedition_success_pts')::double precision, 0) * public.pet_factor(p_user, 'cachorro');
    dog_rec := coalesce((public.pet_def('cachorro') ->> 'lost_cargo_recovery_chance')::double precision, 0) * public.pet_factor(p_user, 'cachorro');
    papagaio := coalesce((public.pet_def('papagaio') ->> 'sales_gold_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'papagaio');
  end if;
  v_res := jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100),
    'golden', least(coalesce((caps -> 'golden_harvest_chance_pct' ->> 'absolute')::double precision, 60) / 100,
                least((crops -> 'golden_harvest' ->> 'cap_permanent')::double precision, ((s ->> 'golden_pct')::double precision + public.jnum(ca, 'golden_harvest_chance_pct')) / 100)
                + public.jnum(cb, 'golden_harvest_chance_pct') / 100),
    'golden_mult', (crops -> 'golden_harvest' ->> 'multiplier')::double precision,
    'harvest_xp', ((s ->> 'harvest_xp_pct')::double precision + case when bot then (fe -> 'botanica' ->> 'harvest_xp_pct')::double precision else 0 end) / 100,
    'account_xp', least(coalesce((caps -> 'account_xp_pct' ->> 'permanent')::double precision, 100) / 100, ((s ->> 'account_xp_pct')::double precision + public.jnum(ca, 'account_xp_pct')) / 100),
    'recurring', (s ->> 'recurring_production_pct')::double precision / 100,
    'extra_fruit', (s ->> 'orchard_extra_fruit_chance')::double precision,
    'seed_discount', least(cap_seed, (-(s ->> 'seed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'seed_discount_pct_per_material')::double precision * (com + 1) else 0 end) / 100),
    'shop_discount', least(cap_seed, -(s ->> 'shop_discount_pct')::double precision / 100),
    'feed_discount', least(cap_seed, (-(s ->> 'feed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision) / 100),
    'animal_production', least(coalesce((caps -> 'animal_production_pct' ->> 'permanent')::double precision, 60) / 100,
                         ((s ->> 'animal_production_pct')::double precision + public.jnum(ca, 'animal_production_pct')) / 100 + gato_animal)
                         + public.jnum(cb, 'animal_production_pct') / 100,
    'animal_cap', coalesce((caps -> 'animal_production_pct' ->> 'absolute')::double precision, 250) / 100,
    'animal_double', (s ->> 'animal_double_pct')::double precision / 100,
    'expansion_cost', (s ->> 'expansion_cost_pct')::double precision / 100,
    'rancheira', ranch,
    'stall_ratio', least((fe -> 'comerciante' ->> 'stall_price_cap')::double precision,
                   base_stall + ((s ->> 'stall_price_pts')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'stall_price_pts_per_material')::double precision * (com + 1) else 0 end) / 100),
    'sales_gold', least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100, (s ->> 'sales_gold_pct')::double precision / 100 + papagaio + (public.jnum(ca, 'sales_gold_pct') + public.jnum(cb, 'sales_gold_pct')) / 100),
    'daily_boost', (s ->> 'daily_boosted_sale')::double precision,
    'cleanup', (s ->> 'cleanup_time_pct')::double precision / 100,
    'tool_cost', (s ->> 'tool_cost_pct')::double precision / 100,
    -- Luvas e Engrenagem: mais trabalho da equipe (a fila automática)
    'team_capacity', ((s ->> 'team_capacity_pct')::double precision + public.jnum(cb, 'team_capacity_pct') + public.jnum(ca, 'team_capacity_pct')
                      + public.jnum(cb, 'team_auto_capacity_pct') + public.jnum(ca, 'team_auto_capacity_pct')) / 100,
    -- Martelo: ferramentas gastam menos; Cesta: mais unidades por colheita; Enxada e Forcado: tarefas gastam menos trabalho
    'tool_wear_cut', least(0.9, (public.jnum(cb, 'cleanup_tool_vehicle_pct') + public.jnum(ca, 'cleanup_tool_vehicle_pct') - public.account_skill(p_user, 'tool_wear_pct')) / 100),
    'yield', least(coalesce((caps -> 'harvest_yield_pct' ->> 'absolute')::double precision, 40) / 100, (public.jnum(cb, 'harvest_yield_pct') + public.jnum(ca, 'harvest_yield_pct')) / 100),
    'crop_work_cut', least(coalesce((caps -> 'work_cost_reduction_pct' ->> 'absolute')::double precision, 40) / 100, (public.jnum(cb, 'crop_work_pct') + public.jnum(ca, 'crop_work_pct')) / 100),
    'ao_work_cut', least(coalesce((caps -> 'work_cost_reduction_pct' ->> 'absolute')::double precision, 40) / 100, (public.jnum(cb, 'animal_orchard_work_pct') + public.jnum(ca, 'animal_orchard_work_pct')) / 100),
    'fishing', (public.jnum(cb, 'fishing_profit_pct') + public.jnum(ca, 'fishing_profit_pct')) / 100,
    'tool_effect', (s ->> 'tool_effect_pct')::double precision / 100,
    'gerente_cut', case when ger >= 0 then ((fe -> 'gerente' ->> 'team_energy_use_pct_base')::double precision
                     + (fe -> 'gerente' ->> 'team_energy_use_pct_per_material')::double precision * ger) / 100 else 0 end,
    'auto_sell', com >= 0,
    'auto_pay', ger >= 0,
    'rare_seed', (case when bot then (fe -> 'botanica' ->> 'rare_seed_chance')::double precision else 0 end + pet_rare)
                 * (1 + (public.jnum(cb, 'rare_seed_chance_pct') + public.jnum(ca, 'rare_seed_chance_pct')) / 100),  -- Lupa
    'seed_refund', case when bot then (fe -> 'botanica' ->> 'seed_refund_chance')::double precision else 0 end,
    'early_unlock', case when (s ->> 'early_unlock_levels')::double precision > 0 and bot_choice is not null
                     then jsonb_build_object('crop', bot_choice, 'levels', (s ->> 'early_unlock_levels')::int) end,
    'gato_rest', gato,
    'exp_success', (s ->> 'expedition_success_pts')::double precision + dog_pts + public.jnum(ca, 'expedition_success_pts') + public.jnum(cb, 'expedition_success_pts'),
    'exp_duration', ((s ->> 'expedition_duration_pct')::double precision - public.jnum(cb, 'expedition_duration_reduction_pct')) / 100,  -- Prancheta e Veículo
    'vehicle_wear', greatest(-0.9, ((s ->> 'vehicle_wear_pct')::double precision - public.jnum(cb, 'vehicle_wear_reduction_pct') - public.jnum(cb, 'cleanup_tool_vehicle_pct')
                    - public.jnum(ca, 'cleanup_tool_vehicle_pct')) / 100),  -- Engrenagem e Martelo
    'route_preview', (s ->> 'route_demand_preview')::double precision,
    'dog_recover', dog_rec,
    'pet', pet);

  -- clima (bônus permanente, com a Botânica +8% por ponto) e evento noturno (teto absoluto; Botânica mestre +15%)
  v_storm := 1 + (public.jnum(ca, 'weather_and_night_event_boost_pct') + public.jnum(cb, 'weather_and_night_event_boost_pct')) / 100;
  wm := (1 + (s ->> 'weather_effect_pct')::double precision / 100) * v_storm;
  em := (1 + (s ->> 'night_event_pct')::double precision / 100) * v_storm;
  cw := v_w -> 'cond_fx'; ew := coalesce(nullif(v_w -> 'event', 'null'::jsonb), '{}');
  -- crescimento: o que já vale no plantio (habilidades) ocupa o teto; o clima entra no que sobra do permanente, o evento no absoluto
  v_base := (v_res ->> 'growth_crop')::double precision;
  v_cg := least((cw ->> 'growth')::double precision * wm, greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100 - v_base));
  v_res := v_res || jsonb_build_object('w_growth', v_cg + least(coalesce((ew ->> 'growth')::double precision, 0) * em + (public.jnum(cb, 'crop_and_orchard_growth_speed_pct') + public.jnum(cb, 'all_speed_pct')) / 100,
    greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'absolute')::double precision, 150) / 100 - v_base - v_cg)));
  v_base := (v_res ->> 'growth_orchard')::double precision;
  v_go := least((cw ->> 'growth')::double precision * wm, greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100 - v_base));
  v_res := v_res || jsonb_build_object('w_growth_orchard', v_go + least(coalesce((ew ->> 'growth')::double precision, 0) * em + (public.jnum(cb, 'crop_and_orchard_growth_speed_pct') + public.jnum(cb, 'all_speed_pct')) / 100,
    greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'absolute')::double precision, 150) / 100 - v_base - v_go)));
  -- XP da conta
  v_xp := least(coalesce((caps -> 'account_xp_pct' ->> 'permanent')::double precision, 100) / 100,
                ((s ->> 'account_xp_pct')::double precision + public.jnum(ca, 'account_xp_pct')) / 100 + (cw ->> 'account_xp')::double precision * wm);
  v_xp := least(coalesce((caps -> 'account_xp_pct' ->> 'absolute')::double precision, 200) / 100, v_xp + coalesce((ew ->> 'account_xp')::double precision, 0) * em + public.jnum(cb, 'account_and_character_xp_pct') / 100);
  v_cxp := (cw ->> 'char_xp')::double precision * wm + coalesce((ew ->> 'char_xp')::double precision, 0) * em
          + (public.jnum(cb, 'account_and_character_xp_pct') + public.jnum(cb, 'character_xp_pct') + public.jnum(ca, 'character_xp_pct')) / 100;
  v_sales := least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100,
                   (v_res ->> 'sales_gold')::double precision + (cw ->> 'sales')::double precision * wm);
  v_warn := (wcfg -> 'night_event' ->> 'warning_minutes')::int;
  if public.pet_level(p_user, 'papagaio') > 0 then
    v_warn := coalesce((public.pet_def('papagaio') ->> 'night_event_warning_minutes')::int, v_warn);
  end if;
  return v_res || jsonb_build_object(
    'w_account_xp', v_xp - (v_res ->> 'account_xp')::double precision,
    'w_sales', v_sales - (v_res ->> 'sales_gold')::double precision,
    'account_xp', v_xp, 'sales_gold', v_sales, 'char_xp', v_cxp,
    'moon', coalesce((ew ->> 'moon')::double precision, 0) * em,
    'forecast_h', least((wcfg -> 'forecast' ->> 'max_hours')::double precision,
                        (wcfg -> 'forecast' ->> 'base_hours')::double precision + (s ->> 'weather_forecast_hours')::double precision),
    'warn_min', v_warn,
    'weather', v_w,
    -- Ampulheta: animais e limpeza andam mais rápido (buff); o Armory acelera os animais para sempre
    'w_speed_animal', (public.jnum(cb, 'all_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100,
    'w_speed_cleanup', (public.jnum(cb, 'all_speed_pct') + public.jnum(cb, 'cleanup_tool_vehicle_pct') + public.jnum(ca, 'cleanup_tool_vehicle_pct')) / 100,
    'coin', public.jnum(cb, 'production_gold_bonus_pct') / 100,
    -- Fôlego: gasto de energia em campo e recuperação no banco
    'card_use_cut', least(1, (public.jnum(cb, 'energy_cost_reduction_pct') + public.jnum(ca, 'energy_cost_reduction_pct')) / 100),
    'card_rest_perm', public.jnum(ca, 'energy_recovery_boost_pct') / 100,
    'card_rest_buff', public.jnum(cb, 'energy_recovery_boost_pct') / 100,
    -- Estrada Livre e Trevo: ficam gravados na expedição que parte agora
    'exp_card', jsonb_build_object('loss_red', public.jnum(cb, 'expedition_loss_reduction_pct') + public.jnum(cb, 'theft_reduction_pct'),
        'crit_pts', public.jnum(cb, 'expedition_crit_pts') + public.jnum(ca, 'expedition_crit_pts') + public.jnum(cb, 'jackpot_pts'),
        'cargo', public.jnum(cb, 'vehicle_cargo_profit_pct') + public.jnum(ca, 'vehicle_cargo_profit_pct') + public.account_skill(p_user, 'cargo_capacity_pct'),
        'profit', public.jnum(cb, 'vehicle_cargo_profit_pct') + public.jnum(ca, 'vehicle_cargo_profit_pct'),
        'crit_val', public.jnum(cb, 'expedition_crit_value_pct'),
        'item_boost', public.jnum(cb, 'item_and_kit_drop_boost_pct') + public.jnum(ca, 'item_drop_boost_pct')),
    'cards', cf,
    -- árvore da conta: energia (no char_energy), lanches, consertos, salários e aves
    'acct_max_energy', public.account_skill(p_user, 'max_energy'),
    -- Sinergia de Equipe: só com os Slots de Campo todos ocupados
    'acct_energy_use', public.account_skill(p_user, 'energy_use_pct')
       + case when (select count(*) from public.characters ch where ch.user_id = p_user and ch.slot = 'field' and public.char_active(ch)) >= (cfg ->> 'field_slots')::int
              then public.account_skill(p_user, 'synergy_energy_pct') else 0 end,
    'low_energy_use', public.account_skill(p_user, 'low_energy_use_pct') / 100,
    'revive_pct', public.account_skill(p_user, 'daily_revive_pct') / 100,
    'first_snack', public.account_skill(p_user, 'first_snack_pct') / 100,
    'instant_growth', public.account_skill(p_user, 'instant_growth_chance_pct') / 100,
    'legendary_fish', public.account_skill(p_user, 'legendary_fish_pct') / 100,
    'mutation', public.account_skill(p_user, 'double_all_pct') / 100,
    'acct_rest', public.account_skill(p_user, 'rest_speed_pct'),
    'snack_boost', public.account_skill(p_user, 'snack_effect_pct') / 100,
    'repair_cut', least(0.9, -public.account_skill(p_user, 'repair_cost_pct') / 100),
    'bird_bonus', public.account_skill(p_user, 'bird_production_pct') / 100);
end;
$function$;

create or replace function public.tick_team(p_user uuid, p_hours double precision, p_frac double precision, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := public.config_get('characters');
  dr jsonb := public.config_get('tools_and_items') -> 'tool_durability_rules';
  snacks jsonb := public.config_get('tools_and_items') -> 'snack_cards';
  c public.characters; en jsonb; v_e double precision; v_h double precision; v_lvl int; v_park boolean; v_qty int; v_rev date;
  v_today date := public.game_day(now()); s jsonb; worked double precision; v_snack_day date;
begin
  for c in select * from public.characters where user_id = p_user for update loop
    en := public.char_energy(c, fx);
    v_e := c.energy; v_h := c.work_hours; v_lvl := c.level; v_park := c.parked; v_qty := c.snack_qty; v_rev := c.revive_day; v_snack_day := c.snack_day;
    if c.leading_id is not null then
      null; -- conduzindo uma expedição: nem trabalha nem descansa
    elsif c.slot = 'field' and not c.parked and public.char_active(c) and c.energy > 0 then
      worked := p_hours * p_frac;
      v_e := v_e - (en ->> 'use')::double precision * worked;
      v_h := v_h + worked * (1 + coalesce((fx ->> 'char_xp')::double precision, 0)); -- neblina e cartas
      update public.tools set durability = greatest(0, durability - (dr ->> 'loss_per_work_hour')::double precision * worked * (1 - coalesce((fx ->> 'tool_wear_cut')::double precision, 0)))
        where user_id = p_user and class_id = c.class_id;
      if v_e <= 0 then
        v_e := 0;
        if greatest(public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'), coalesce((fx ->> 'revive_pct')::double precision, 0) * (en ->> 'max')::double precision) > 0
           and v_rev is distinct from v_today then
          -- Segundo Fôlego: volta com 30% da energia máxima, 1×/dia, sem ir ao banco
          v_e := greatest(public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'), coalesce((fx ->> 'revive_pct')::double precision, 0) * (en ->> 'max')::double precision); v_rev := v_today;
        else
          v_park := true;
        end if;
      end if;
    else
      v_e := least((en ->> 'max')::double precision, v_e + (en ->> 'rest')::double precision * p_hours);
      if v_park and v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
    end if;
    -- lanche automático abaixo de 15% da energia máxima
    if v_qty > 0 and c.snack_id is not null then
      s := (select x from jsonb_array_elements(snacks) x where x ->> 'id' = c.snack_id);
      while v_qty > 0 and v_e < (s ->> 'auto_trigger_below_energy_pct')::double precision / 100 * (en ->> 'max')::double precision loop
        -- Café Forte: o 1º lanche do dia de cada personagem recupera mais
        v_e := least((en ->> 'max')::double precision, v_e + (s ->> 'energy_restore')::double precision * (1 + coalesce((fx ->> 'snack_boost')::double precision, 0)
               + case when v_snack_day is distinct from v_today then coalesce((fx ->> 'first_snack')::double precision, 0) else 0 end));
        v_snack_day := v_today;
        v_qty := v_qty - 1;
        if v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
      end loop;
    end if;
    -- nível do personagem: (10 + 1,5 × nível) horas para o próximo
    while v_lvl < (cfg -> 'character_level' ->> 'max')::int
      and v_h >= (cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl loop
      v_h := v_h - ((cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl);
      v_lvl := v_lvl + 1;
    end loop;
    if v_lvl = (cfg -> 'character_level' ->> 'max')::int then v_h := 0; end if;
    if v_lvl > c.level then perform public.mission_progress(p_user, 'char_level', v_lvl - c.level); end if;
    update public.characters set energy = v_e, work_hours = v_h, level = v_lvl, parked = v_park, snack_qty = v_qty,
        snack_id = case when v_qty = 0 then null else snack_id end, revive_day = v_rev, snack_day = v_snack_day
      where user_id = p_user and class_id = c.class_id;
  end loop;
end;
$function$;

drop function if exists public.equip_def(p_item text);
drop function if exists public.item_effect(c public.characters, p_key text);

-- itens de funcionário acabaram (v3, 01/11): os personagens não têm mais Vestimenta nem Amuleto.
-- Os itens antigos continuam no inventário de quem tinha (nada do ledger muda).
alter table public.characters drop column if exists cloth_id, drop column if exists amulet_id;
