-- Reformulação v3, ajuste (aprovado pelo dono em 01/11): as cartas de ferramenta substituem a raridade das ferramentas.
-- Cada personagem tem 1 ferramenta só (Enxada, Forcado, Martelo, Balança, Prancheta, Lupa); ela melhora SOZINHA com o
-- nível da conta (mesma curva de trabalho dos antigos materiais), sem compra na Forja. Desgaste e conserto continuam.
-- Pesca: a Vara de Pescar vem com o Lago, gasta a cada rede recolhida e se conserta com ouro; abaixo de 30% rende a metade.
-- Limpeza (config lots.json): sem Ferreiro em campo como estava com ele; com o Ferreiro em campo 3× mais rápida.
alter table public.farms add column rod_durability double precision not null default 100;

-- nível da ferramenta pelo nível da conta (o maior "material" liberado)
create or replace function public.tool_tier(p_level int)
returns text language sql stable set search_path = '' as $$
  select x ->> 'id' from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') x
  where (x ->> 'unlock_level')::int <= p_level order by (x ->> 'unlock_level')::int desc limit 1
$$;

-- só sobe (nunca desce): quem já tinha comprado um material mais alto fica com ele
create or replace function public.tools_autotier(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_tier text; v_idx int;
begin
  select public.tool_tier(level) into v_tier from public.farms where user_id = p_user;
  v_idx := public.material_idx(v_tier);
  update public.tools set material = v_tier where user_id = p_user and public.material_idx(material) < v_idx;
end;
$$;

create or replace function public.upgrade_tool(p_class text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin raise exception 'a ferramenta melhora sozinha com o nível' using errcode = 'check_violation'; end;
$$;

-- conserto da Vara de Pescar: preço do conserto da ferramenta do nível
create or replace function public.rod_repair_cost(p_user uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select round((public.material_def(public.tool_tier(f.level)) ->> 'repair_cost_gold')::numeric
    * (1 + (public.team_fx(p_user) ->> 'tool_cost')::numeric) * (1 - (public.team_fx(p_user) ->> 'repair_cut')::numeric)
    * (100 - f.rod_durability)::numeric / 100, 2)
  from public.farms f where f.user_id = p_user
$$;

create or replace function public.repair_rod()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_cost numeric; v_dur double precision;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select rod_durability into v_dur from public.farms where user_id = v_user for update;
  if v_dur >= 100 then raise exception 'a vara já está inteira' using errcode = 'check_violation'; end if;
  v_cost := public.rod_repair_cost(v_user);
  perform public.ledger_post(v_user, -v_cost, 'rod_repair', jsonb_build_object('durability', round(v_dur::numeric, 1)));
  update public.farms set rod_durability = 100 where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;


create or replace function public.fish_collect(p_user uuid, p_t double precision, fx jsonb, p_team boolean)
returns int language plpgsql security definer set search_path = '' as $$
declare c jsonb := public.config_get('fishing'); f public.farms; n int; sp jsonb; v_val double precision; v_qty int; v_xp numeric; v_cyc double precision;
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
    values (null, 'fish.collect', p_user, jsonb_build_object('cycles', n, 'fish', sp ->> 'id', 'qty', v_qty, 'team', p_team));
  return v_qty;
end;
$$;

create or replace function public.fish_state(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when f.fish_t is null or not public.lake_ready(p_user, f.farm_time) then null else jsonb_build_object(
    'cycles', public.fish_cycles(p_user, f.farm_time), 'max', (c ->> 'max_cycles')::int,
    'fish_t', f.fish_t, 'cycle_s', (c ->> 'cycle_minutes')::int * 60, 'species', public.fish_species(f.level) ->> 'id',
    'rod', round(f.rod_durability::numeric, 1), 'rod_repair', public.rod_repair_cost(p_user)) end
  from public.farms f, (select public.config_get('fishing') c) cfg where f.user_id = p_user
$$;


create or replace function public.item_price(p_item text)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce((public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric,
    (select (x -> 'product' ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('animals') -> 'animals') x
     where x -> 'product' ->> 'id' = p_item limit 1),
    (select (x ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('fishing') -> 'species') x where x ->> 'id' = p_item limit 1))
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
        'cargo', public.jnum(cb, 'vehicle_cargo_profit_pct') + public.jnum(ca, 'vehicle_cargo_profit_pct'),
        'profit', public.jnum(cb, 'vehicle_cargo_profit_pct') + public.jnum(ca, 'vehicle_cargo_profit_pct'),
        'crit_val', public.jnum(cb, 'expedition_crit_value_pct'),
        'item_boost', public.jnum(cb, 'item_and_kit_drop_boost_pct') + public.jnum(ca, 'item_drop_boost_pct')),
    'cards', cf,
    -- árvore da conta: energia (no char_energy), lanches, consertos, salários e aves
    'acct_max_energy', public.account_skill(p_user, 'max_energy'),
    'acct_energy_use', public.account_skill(p_user, 'energy_use_pct'),
    'acct_rest', public.account_skill(p_user, 'rest_speed_pct'),
    'snack_boost', public.account_skill(p_user, 'snack_effect_pct') / 100,
    'repair_cut', least(0.9, -public.account_skill(p_user, 'repair_cost_pct') / 100),
    'bird_bonus', public.account_skill(p_user, 'bird_production_pct') / 100);
end;
$function$;

create or replace function public.advance_farm(p_user uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.farms;
  v_farm jsonb := public.config_get('farm');
  v_work jsonb := public.config_get('crops') -> 'rules' -> 'work_units';
  v_plant_cost double precision := coalesce((v_work ->> 'plant')::double precision, 0.5);
  v_harvest_cost double precision := coalesce((v_work ->> 'harvest')::double precision, 0.5);
  v_step double precision := coalesce((public.config_get('characters') ->> 'step_minutes')::double precision, 10) * 60;
  v_cap_h double precision := coalesce((v_farm ->> 'labor_bank_cap_hours')::double precision, 1);
  v_end timestamptz;
  t0 double precision; t1 double precision; seg0 double precision; seg1 double precision;
  t_cur double precision; labor double precision; labor0 double precision; used double precision;
  rate double precision; cap double precision; fx jsonb; tr jsonb;
  v_gold numeric; v_seed_spent numeric; v_refund numeric; v_plantings int; v_seed numeric; v_feed numeric; v_f numeric;
  e record; lt double precision; te double precision; v_real timestamptz; v_w jsonb; v_g double precision; v_cut double precision; v_help jsonb;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  labor := f.labor_bank;
  seg0 := t0;
  perform public.weather_ensure(p_user, f.synced_at, p_now);
  perform public.mission_ensure(p_user, p_now);
  -- a troca de fuso marcada vale a partir da meia-noite combinada
  update public.profiles set timezone = tz_pending, tz_pending = null, tz_pending_at = null
    where id = p_user and tz_pending is not null and tz_pending_at <= f.synced_at;

  -- pesca: a rede começa a encher quando o Lago fica pronto
  update public.farms fa set fish_t = (select min(ol.ready_at) from public.owned_lots ol
      join lateral (select x from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = ol.lot_id) d on true
      where ol.user_id = p_user and d.x ->> 'type' = 'pasto_lago')
    where fa.user_id = p_user and fa.fish_t is null and public.lake_ready(p_user, t1);

  perform public.tools_autotier(p_user);
  while seg0 < t1 loop
    -- relógio real do passo: o clima e o evento valem pela hora local do jogador
    v_real := f.synced_at + make_interval(secs => seg0 - t0);
    perform set_config('vif.at', v_real::text, true);
    v_w := public.weather_now(p_user, v_real);
    v_cut := extract(epoch from ((v_w ->> 'next')::timestamptz - v_real));
    -- cartas: buffs que acabaram pagam a Moeda da Sorte; o passo também corta no fim do próximo buff
    perform public.buffs_expire(p_user, v_real);
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.card_buffs where user_id = p_user and ends_at > v_real));
    -- ajuda de vizinho: +10% de crescimento no lote enquanto durar (o passo corta no fim)
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.lot_helps where owner = p_user and kind = 'growth' and ends_at > v_real));
    v_help := (select coalesce(jsonb_object_agg(lot_id, g), '{}') from (select lot_id, sum(pct) / 100 g from public.lot_helps
               where owner = p_user and kind = 'growth' and started_at <= v_real and ends_at > v_real group by lot_id) h);
    seg1 := least(t1, seg0 + v_step, seg0 + greatest(1, coalesce(v_cut, v_step)));
    -- evento que valeu para a conta (no máximo 1 a cada 20 h, mesmo trocando de fuso)
    if coalesce((v_w -> 'event' ->> 'active')::boolean, false) then
      update public.farms set last_event_start = (v_w -> 'event' ->> 'start')::timestamptz
        where user_id = p_user and last_event_start is distinct from (v_w -> 'event' ->> 'start')::timestamptz;
      -- missão semanal: produção ativa durante o evento (conta 1 vez por evento)
      if (select event_credit from public.farms where user_id = p_user) is distinct from (v_w -> 'event' ->> 'start')::timestamptz
         and (exists (select 1 from public.plots where user_id = p_user and state = 'growing')
              or exists (select 1 from public.trees where user_id = p_user and fruit_id is not null)
              or exists (select 1 from public.animals where user_id = p_user and state = 'growing')) then
        update public.farms set event_credit = (v_w -> 'event' ->> 'start')::timestamptz where user_id = p_user;
        perform public.mission_progress(p_user, 'night_events', 1);
      end if;
    end if;
    -- salário das meias-noites até o fim deste passo (no relógio real)
    perform public.process_payday(p_user, f.synced_at + make_interval(secs => seg1 - t0));
    fx := public.team_fx(p_user);
    if (fx ->> 'auto_pay')::boolean then perform public.pay_debts(p_user); end if;
    perform public.rotate_team(p_user);
    fx := public.team_fx(p_user);
    tr := public.team_rate(p_user, fx);
    -- Sol forte, Calor Dourado e ajuda de vizinho (só no lote ajudado): quem está crescendo anda mais rápido neste passo
    v_g := coalesce((fx ->> 'w_growth')::double precision, 0);
    if v_g > 0 or v_help <> '{}' then
      update public.plots pl set ready_at = case when (pl.ready_at - seg0) / (1 + x.g) <= seg1 - seg0 then seg0 + (pl.ready_at - seg0) / (1 + x.g)
                                                 else pl.ready_at - (seg1 - seg0) * x.g end
        from (select p2.plot_id, v_g + coalesce((v_help ->> split_part(p2.plot_id, '-', 1))::double precision, 0) g
              from public.plots p2 where p2.user_id = p_user) x
        where pl.user_id = p_user and pl.plot_id = x.plot_id and x.g > 0 and pl.state = 'growing' and pl.ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_growth_orchard')::double precision, 0);
    if v_g > 0 or v_help <> '{}' then
      update public.trees t set ready_at = case when (t.ready_at - seg0) / (1 + x.g) <= seg1 - seg0 then seg0 + (t.ready_at - seg0) / (1 + x.g)
                                                else t.ready_at - (seg1 - seg0) * x.g end
        from (select t2.lot_id, t2.slot, v_g + coalesce((v_help ->> t2.lot_id)::double precision, 0) g
              from public.trees t2 where t2.user_id = p_user) x
        where t.user_id = p_user and t.lot_id = x.lot_id and t.slot = x.slot and x.g > 0 and t.fruit_id is not null and t.ready_at > seg0;
    end if;
    -- Ampulheta e Armory: animais e limpeza de lote andam mais rápido
    v_g := coalesce((fx ->> 'w_speed_animal')::double precision, 0);
    if v_g > 0 then
      update public.animals set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                                else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and state = 'growing' and ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_speed_cleanup')::double precision, 0);
    if v_g > 0 then
      update public.owned_lots set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                                   else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and ready_at > seg0;
    end if;
    rate := (tr ->> 'working')::double precision / 3600.0;
    cap := (tr ->> 'nominal')::double precision * v_cap_h;
    if cap > 0 then labor := least(labor, cap); end if; -- teto do trabalho guardado (ninguém em campo: guarda o que tinha)
    cap := greatest(cap, labor);
    labor0 := labor; used := 0; t_cur := seg0;
    select gold into v_gold from public.wallets where user_id = p_user;
    v_seed_spent := 0; v_refund := 0; v_plantings := 0;
    -- animais com fome voltam a produzir quando há ouro para a ração (sem gastar trabalho)
    v_feed := public.animals_feed_hungry(p_user, seg0, fx, v_gold);

    loop
      i := i + 1;
      exit when i > 20000; -- trava de segurança
      select * into e from (
        select 'harvest'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, v_harvest_cost * (1 - coalesce((fx ->> 'crop_work_cut')::double precision, 0)) as cost
          from public.plots pl
          where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= seg1
        union all
        select 'harvest_tree', t.lot_id, t.slot, t.ready_at, v_harvest_cost * (1 - coalesce((fx ->> 'ao_work_cut')::double precision, 0))
          from public.trees t
          where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= seg1
        union all
        select 'collect', a.house_id, a.slot, a.ready_at, v_harvest_cost * (1 - coalesce((fx ->> 'ao_work_cut')::double precision, 0))
          from public.animals a
          where a.user_id = p_user and a.state = 'growing' and a.ready_at <= seg1
        union all
        select 'fish', 'lago', 0, fa.fish_t + (fc ->> 'max_cycles')::double precision * (fc ->> 'cycle_minutes')::double precision * 60, v_harvest_cost
          from public.farms fa, (select public.config_get('fishing') fc) q2
          where fa.user_id = p_user and fa.fish_t is not null and coalesce((fc -> 'team' ->> 'collects_when_full')::boolean, false)
            and fa.fish_t + (fc ->> 'max_cycles')::double precision * (fc ->> 'cycle_minutes')::double precision * 60 <= seg1
        union all
        select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost * (1 - coalesce((fx ->> 'crop_work_cut')::double precision, 0))
          from public.plots pl join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
          where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null
            and greatest(coalesce(pl.free_since, t0), ol.ready_at) <= seg1
      ) q
      order by avail, key, slot
      limit 1;
      exit when not found;

      -- quando a equipe terá o trabalho necessário
      lt := least(cap, labor + rate * (greatest(e.avail, t_cur) - t_cur));
      if lt >= e.cost then te := greatest(e.avail, t_cur);
      elsif rate > 0 then te := greatest(e.avail, t_cur) + (e.cost - lt) / rate;
      else te := seg1 + 1; end if;
      exit when te > seg1; -- a fila é única: se a primeira tarefa não cabe, nenhuma cabe neste passo

      if e.kind = 'plant' then
        v_seed := public.seed_price((select crop_id from public.plots where user_id = p_user and plot_id = e.key), fx);
        if v_gold - v_seed_spent - v_feed < v_seed then
          update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
          continue;
        end if;
        v_seed_spent := v_seed_spent + public.plant_plot(p_user, e.key, (select crop_id from public.plots where user_id = p_user and plot_id = e.key), te, fx);
        v_plantings := v_plantings + 1;
      elsif e.kind = 'harvest' then
        v_refund := v_refund + public.harvest_plot(p_user, e.key, te, fx);
      elsif e.kind = 'fish' then
        perform public.fish_collect(p_user, te, fx, true);
      elsif e.kind = 'collect' then
        perform public.animal_collect(p_user, e.key, e.slot, te, fx, true);
        v_f := public.animal_start(p_user, e.key, e.slot, te, fx, v_gold - v_seed_spent - v_feed);
        v_feed := v_feed + coalesce(v_f, 0);
      else
        perform public.harvest_tree(p_user, e.key, e.slot, te, fx);
      end if;
      -- se precisou esperar, no instante te o trabalho juntado é exatamente o custo: sobra 0
      -- (corrige a fase 2, que descontava a espera duas vezes e deixava o trabalho fora do jogo mais lento)
      labor := case when lt >= e.cost then lt - e.cost else 0 end;
      used := used + e.cost;
      t_cur := te;
    end loop;

    if seg1 > t_cur then labor := least(cap, labor + rate * (seg1 - t_cur)); end if;
    labor := greatest(0, labor);
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds', jsonb_build_object('plantings', v_plantings, 'farm_time', round(seg1::numeric, 1)));
    end if;
    if v_refund > 0 then
      perform public.ledger_post(p_user, round(v_refund, 2), 'seed_refund', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    if v_feed > 0 then
      perform public.ledger_post(p_user, -round(v_feed, 2), 'feed', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    -- energia, nível e desgaste na fração do passo em que a equipe produziu trabalho
    perform public.tick_team(p_user, (seg1 - seg0) / 3600.0,
      case when rate > 0 then least(1, greatest(0, (labor - labor0 + used) / (rate * (seg1 - seg0)))) else 0 end, fx);
    -- missão: 3 personagens trabalhando em campo ao mesmo tempo
    if rate > 0 and (select count(*) from public.characters ch where ch.user_id = p_user and ch.slot = 'field' and not ch.parked
                     and ch.energy > 0 and ch.leading_id is null and public.char_active(ch)) >= 3 then
      perform public.mission_progress(p_user, 'field3_hours', ((seg1 - seg0) / 3600.0)::numeric);
    end if;
    if public.auto_sell(p_user, fx) > 0 then
      update public.plots set stalled_reason = null, free_since = seg1 where user_id = p_user and stalled_reason = 'sem_ouro';
    end if;
    seg0 := seg1;
  end loop;

  perform set_config('vif.at', '', true);
  perform public.buffs_expire(p_user, p_now);
  perform public.cards_maintain(p_user);
  perform public.vehicles_unlock(p_user);
  perform public.tools_autotier(p_user);
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
end;
$function$;
