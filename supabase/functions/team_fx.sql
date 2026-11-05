-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
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
  ranch boolean := false; fisher boolean := false;
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
    if c.class_id = 'pescador' then fisher := true; end if;
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
    'pescador', fisher,
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
