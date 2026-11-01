-- Reformulação v3: Árvore de Passivas (aprovada pelo dono em 01/11). 3 caminhos (Natureza, Comércio, Resistência) com
-- 4 nós de até 5 pontos e uma Ultimate de 5 pontos cada. A abre B e C (1 ponto); B ou C com 3 abre D; a Ultimate pede
-- D e 15 pontos no ramo. 1 ponto por nível. As passivas antigas saem: os pontos gastos voltam.
alter table public.characters add column snack_day date;   -- dia do 1º lanche (Café Forte)
update public.farms set account_skills = '{}'::jsonb where account_skills <> '{}'::jsonb;

create or replace function public.account_node(p_node text)
returns jsonb language sql stable set search_path = '' as $$
  select n || jsonb_build_object('branch', b ->> 'id') from jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b,
         jsonb_array_elements(b -> 'nodes') n where n ->> 'id' = p_node limit 1
$$;

-- efeito somado: pontos × valor por ponto, em todos os efeitos de todos os nós
create or replace function public.account_skill(p_user uuid, p_effect text)
returns double precision language sql stable set search_path = '' as $$
  select coalesce(sum(coalesce((f.account_skills ->> (n ->> 'id'))::double precision, 0) * (e ->> 'per_point')::double precision), 0)
  from public.farms f, jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b,
       jsonb_array_elements(b -> 'nodes') n, jsonb_array_elements(n -> 'effects') e
  where f.user_id = p_user and e ->> 'effect' = p_effect
$$;

-- pontos gastos (nível × custo do nó), no total ou só num ramo
create or replace function public.account_spent(p_user uuid, p_branch text default null)
returns int language sql stable set search_path = '' as $$
  select coalesce(sum(coalesce((f.account_skills ->> (n ->> 'id'))::int, 0) * (n ->> 'cost')::int), 0)::int
  from public.farms f, jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b, jsonb_array_elements(b -> 'nodes') n
  where f.user_id = p_user and (p_branch is null or b ->> 'id' = p_branch)
$$;

create or replace function public.account_skill_add(p_node text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); nd jsonb := public.account_node(p_node); f public.farms; v_cur int; r jsonb; ok boolean;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if nd is null then raise exception 'habilidade não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  v_cur := coalesce((f.account_skills ->> p_node)::int, 0);
  if v_cur >= (nd ->> 'max')::int then raise exception 'habilidade no máximo' using errcode = 'check_violation'; end if;
  if public.account_spent(v_user) + (nd ->> 'cost')::int > public.account_points(v_user) then raise exception 'sem pontos de habilidade' using errcode = 'check_violation'; end if;
  -- caminho: todos os "requires", ao menos um dos "requires_any" e os pontos do ramo
  for r in select jsonb_array_elements(coalesce(nd -> 'requires', '[]')) loop
    if coalesce((f.account_skills ->> (r ->> 'node'))::int, 0) < (r ->> 'min')::int then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  end loop;
  if nd ? 'requires_any' then
    select bool_or(coalesce((f.account_skills ->> (x ->> 'node'))::int, 0) >= (x ->> 'min')::int) into ok from jsonb_array_elements(nd -> 'requires_any') x;
    if not ok then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  end if;
  if public.account_spent(v_user, nd ->> 'branch') < coalesce((nd ->> 'requires_branch_points')::int, 0) then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  update public.farms set account_skills = account_skills || jsonb_build_object(p_node, v_cur + 1) where user_id = v_user;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'skill.add', v_user, jsonb_build_object('node', p_node, 'to', v_cur + 1));
  return public.farm_state(v_user);
end;
$$;


create or replace function public.account_tree_state(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('skills', f.account_skills, 'points', public.account_points(p_user),
    'spent', public.account_spent(p_user),
    'free_reset', f.account_reset_week is distinct from to_char(public.game_day(now()), 'IYYY-IW'),
    'reset_cost', round(public.ref_income(f.level) * (public.config_get('characters') -> 'account_tree' ->> 'extra_reset_cost_R_ratio')::numeric, 2))
  from public.farms f where f.user_id = p_user
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
  dog_pts double precision := 0; dog_rec double precision := 0; it_double double precision := 0; it_animal double precision := 0;
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
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    if pet ->> 'id' = 'gato' then
      gato := (select (x ->> 'energy_recovery_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
      gato_animal := (select (x ->> 'animal_production_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'cachorro' then
      dog_pts := (select (x ->> 'expedition_success_pts')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'cachorro') * (pet ->> 'factor')::double precision;
      dog_rec := (select (x ->> 'lost_cargo_recovery_chance')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'cachorro') * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'papagaio' then
      papagaio := (select (x ->> 'sales_gold_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio') / 100 * (pet ->> 'factor')::double precision;
    end if;
  end if;
  -- amuletos de quem está em campo: Trevo (colheita dupla) e Pena (produção animal)
  select coalesce(sum(public.item_effect(ch, 'double_harvest_chance_pct')), 0) / 100, coalesce(sum(public.item_effect(ch, 'animal_production_pct')), 0) / 100
    into it_double, it_animal from public.characters ch where ch.user_id = p_user and public.char_active(ch);
  v_res := jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100 + it_double),
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
                         ((s ->> 'animal_production_pct')::double precision + public.jnum(ca, 'animal_production_pct')) / 100 + gato_animal + it_animal)
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
  if pet ->> 'id' = 'papagaio' then
    v_warn := coalesce((select (x ->> 'night_event_warning_minutes')::int from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio'), v_warn);
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

create or replace function public.char_energy(c characters, fx jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + public.item_effect(c, 'max_energy_bonus') + coalesce((fx ->> 'acct_max_energy')::double precision, 0),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'absolute')::double precision, 100) / 100,
             (1 - coalesce((fx ->> 'card_use_cut')::double precision, 0)) * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + (public.skill_effect(c.class_id, c.skills, 'energy_use_pct') + coalesce((fx ->> 'acct_energy_use')::double precision, 0)) / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * case when c.energy < 0.3 * ((ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + public.item_effect(c, 'max_energy_bonus') + coalesce((fx ->> 'acct_max_energy')::double precision, 0))
                                  then 1 + coalesce((fx ->> 'low_energy_use')::double precision, 0) else 1 end
                           * (1 - public.item_effect(c, 'energy_cost_reduction_pct') / 100)
                           * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 - (ch -> 'pets' ->> 'per_level_energy_use_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end)),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'absolute')::double precision, 200) / 100,
             coalesce((fx ->> 'card_rest_buff')::double precision, 0) + least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + (public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') + coalesce((fx ->> 'acct_rest')::double precision, 0)) / 100) * (1 + coalesce((fx ->> 'card_rest_perm')::double precision, 0)))))
  from cfg
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
      v_h := v_h + worked * (1 + public.item_effect(c, 'character_xp_pct') / 100 + coalesce((fx ->> 'char_xp')::double precision, 0)); -- Relógio de Bolso + neblina
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

create or replace function public.plant_plot(p_user uuid, p_plot text, p_crop text, p_t double precision, fx jsonb, p_rarity text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c jsonb := public.crop_def(p_crop); v_seed numeric;
begin
  v_seed := case when p_rarity is null then round((c ->> 'seed_cost')::numeric * (1 - (fx ->> 'seed_discount')::numeric), 2) else 0 end;
  update public.plots
    set state = 'growing', planted_crop_id = p_crop, planted_kind = c ->> 'kind', planted_at = p_t, harvests_done = 0,
        ready_at = case when public.rand01() < coalesce((fx ->> 'instant_growth')::double precision, 0) then p_t  -- Mão Verde: nasce pronta
                        else p_t + (c ->> 'grow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision) end,
        free_since = null, stalled_reason = null, rarity = p_rarity, seed_paid = v_seed
    where user_id = p_user and plot_id = p_plot;
  -- missão "plante um cultivo dos seus últimos níveis"
  if (c ->> 'unlock_level')::int >= (select level from public.farms where user_id = p_user) - (public.config_get('missions') ->> 'plant_top_window_levels')::int then
    perform public.mission_progress(p_user, 'plant_top', 1);
  end if;
  return v_seed;
end;
$function$;

create or replace function public.harvest_plot(p_user uuid, p_plot text, p_t double precision, fx jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_q int; pl public.plots; c jsonb; v_done int; v_total int; m double precision; rm double precision; v_refund numeric := 0;
begin
  select * into pl from public.plots where user_id = p_user and plot_id = p_plot for update;
  c := public.crop_def(pl.planted_crop_id);
  rm := public.rarity_mult(pl.rarity);
  m := rm * (1 + case when c ->> 'kind' = 'recurring' then (fx ->> 'recurring')::double precision else 0 end);
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  if c ->> 'kind' = 'crop' and public.rand01() < (fx ->> 'double_crop')::double precision then m := m * 2; end if;
  if public.rand01() < coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- Mutação Genética
  m := m * (1 + coalesce((fx ->> 'yield')::double precision, 0));  -- Cesta
  v_q := public.round_rand((c ->> 'units_per_harvest')::double precision * m);
  insert into public.silo (user_id, item_id, qty) values (p_user, pl.planted_crop_id, v_q)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.produced(p_user, pl.planted_crop_id, v_q, (c ->> 'xp_per_harvest')::numeric * rm::numeric, 'crop');
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, pl.planted_crop_id, fx);
  v_done := pl.harvests_done + 1;
  v_total := coalesce((c ->> 'harvests_per_planting')::int, 1);
  if (c ->> 'kind') = 'recurring' and v_done < v_total then
    update public.plots set harvests_done = v_done,
        ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision)
      where user_id = p_user and plot_id = p_plot;
  else
    if pl.seed_paid > 0 and public.rand01() < (fx ->> 'seed_refund')::double precision then v_refund := pl.seed_paid; end if;
    update public.plots set state = 'empty', planted_crop_id = null, planted_kind = null, planted_at = null, ready_at = null,
        harvests_done = 0, free_since = p_t, rarity = null, seed_paid = 0
      where user_id = p_user and plot_id = p_plot;
  end if;
  return v_refund;
end;
$function$;

create or replace function public.harvest_tree(p_user uuid, p_lot text, p_slot integer, p_t double precision, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tr public.trees; c jsonb; m double precision; rm double precision; v_qty int;
begin
  select * into tr from public.trees where user_id = p_user and lot_id = p_lot and slot = p_slot for update;
  c := public.crop_def(tr.fruit_id);
  rm := case when tr.rare_left > 0 then public.rarity_mult(tr.rarity) else 1 end;
  m := rm;
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  if public.rand01() < coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- Mutação Genética
  m := m * (1 + coalesce((fx ->> 'yield')::double precision, 0));  -- Cesta
  v_qty := public.round_rand((c ->> 'units_per_harvest')::double precision * m);
  if public.rand01() < (fx ->> 'extra_fruit')::double precision then v_qty := v_qty + 1; end if;
  insert into public.silo (user_id, item_id, qty) values (p_user, tr.fruit_id, v_qty)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.produced(p_user, tr.fruit_id, v_qty, (c ->> 'xp_per_harvest')::numeric * rm::numeric, 'crop');
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, tr.fruit_id, fx);
  update public.trees set ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_orchard')::double precision),
      rare_left = greatest(0, rare_left - 1), rarity = case when rare_left <= 1 then null else rarity end
    where user_id = p_user and lot_id = p_lot and slot = p_slot;
end;
$function$;

create or replace function public.animal_collect(p_user uuid, p_house text, p_slot integer, p_t double precision, fx jsonb, p_team boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.animals; d jsonb; r jsonb := public.config_get('animals') -> 'rules'; m double precision; bonus double precision; v_qty int;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  d := public.animal_def(a.animal_id);
  bonus := coalesce((fx ->> 'animal_production')::double precision, 0)
         + case when (d ->> 'is_bird')::boolean then coalesce((fx ->> 'bird_bonus')::double precision, 0) else 0 end;
  m := public.rarity_mult(a.rarity) * (1 + least(bonus, coalesce((fx ->> 'animal_cap')::double precision, 0.6)))
     * case when p_team then case when coalesce((fx ->> 'rancheira')::boolean, false) then (r -> 'collector_efficiency' ->> 'rancheira')::double precision
                                  else (r -> 'collector_efficiency' ->> 'other_class')::double precision end else 1 end;
  if public.rand01() < coalesce((fx ->> 'animal_double')::double precision, 0) + coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- + Mutação Genética
  v_qty := public.round_rand(coalesce((r ->> 'units_per_collect')::double precision, 1) * m);
  if v_qty > 0 then
    insert into public.silo (user_id, item_id, qty) values (p_user, d -> 'product' ->> 'id', v_qty)
      on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
    perform public.produced(p_user, d -> 'product' ->> 'id', v_qty, (d ->> 'xp_per_collect')::numeric, 'animal');
  end if;
  perform public.add_xp(p_user, round((d ->> 'xp_per_collect')::numeric * (1 + (fx ->> 'account_xp')::numeric), 2));
  update public.animals set ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_qty;
end;
$function$;

create or replace function public.fish_collect(p_user uuid, p_t double precision, fx jsonb, p_team boolean)
returns int language plpgsql security definer set search_path = '' as $$
declare v_leg boolean := false; c jsonb := public.config_get('fishing'); f public.farms; n int; sp jsonb; v_val double precision; v_qty int; v_xp numeric; v_cyc double precision;
begin
  select * into f from public.farms where user_id = p_user for update;
  n := public.fish_cycles(p_user, p_t);
  if n < 1 then return 0; end if;
  v_cyc := (c ->> 'cycle_minutes')::double precision * 60;
  sp := public.fish_species(f.level);
  -- valor: 8% da renda do nível por dia ÷ 12 ciclos, × ciclos, × Vara de Pescar; a equipe rende 60%
  v_val := public.ref_income(f.level)::double precision * (c ->> 'value_share_of_R')::double precision / (c ->> 'cycles_per_day_reference')::double precision
         * n * (1 + coalesce((fx ->> 'fishing')::double precision, 0))
         * case when f.rod_durability < (c -> 'rod' ->> 'low_threshold')::double precision then (c -> 'rod' ->> 'low_multiplier')::double precision else 1 end
         * case when p_team then (c -> 'team' ->> 'efficiency')::double precision else 1 end;
  -- Mestre Pescador: peixe Lendário vale o dobro
  if public.rand01() < coalesce((fx ->> 'legendary_fish')::double precision, 0) then v_val := v_val * 2; v_leg := true; end if;
  v_qty := greatest(1, public.round_rand(v_val / (sp ->> 'fair_price_per_unit')::double precision));
  insert into public.silo (user_id, item_id, qty) values (p_user, sp ->> 'id', v_qty)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  v_xp := round((public.config_get('levels') -> 'levels' -> (greatest(1, least(49, f.level)) - 1) ->> 'xp_to_next')::numeric
               * (c ->> 'xp_per_cycle_ratio_of_level')::numeric * n, 2);
  perform public.produced(p_user, sp ->> 'id', v_qty, v_xp, 'fish');
  perform public.add_xp(p_user, round(v_xp * (1 + coalesce((fx ->> 'account_xp')::numeric, 0)), 2));
  update public.farms set fish_t = case when n >= (c ->> 'max_cycles')::int then p_t else fish_t + n * v_cyc end,
      rod_durability = greatest(0, rod_durability - (c -> 'rod' ->> 'wear_per_cycle')::double precision * n * (1 - coalesce((fx ->> 'tool_wear_cut')::double precision, 0)))
    where user_id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'fish.collect', p_user, jsonb_build_object('cycles', n, 'fish', sp ->> 'id', 'qty', v_qty, 'team', p_team, 'legendary', v_leg));
  return v_qty;
end;
$$;
