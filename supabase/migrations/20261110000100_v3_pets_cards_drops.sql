-- Reformulação v3 (pedido do dono em 01/11/2026):
-- 1) Pets novos: os 3 vivem na fazenda ao mesmo tempo, chegam sozinhos no nível de cada um (sem adoção, sem vínculo
--    com personagem) e trazem um achado a cada X horas para o jogador clicar (Cachorro: baú com ouro e chance de carta;
--    Gato: energia para a equipe; Papagaio: moedas). O carinho (1 por dia por pet) sobe o nível.
-- 2) Expedições: o achado agora é só carta (acabam itens de funcionário, Kits de Reforma e Escrituras).
-- 3) Veículos: sem raridade e sem reforma (a cara do veículo vem da carta Veículo).
-- Nada do ledger é apagado; itens e Kits antigos ficam no inventário, sem uso.

alter table public.pets add column if not exists find_t double precision;
drop index if exists public.pets_one_active;
update public.pets set active = true, linked_class = null;
update public.pets p set find_t = f.farm_time from public.farms f where f.user_id = p.user_id and p.find_t is null;
-- itens de funcionário acabaram: tira o que estava vestido (o item volta para o inventário, sem uso)
insert into public.inventory (user_id, item_id, qty)
  select user_id, x, 1 from (select user_id, cloth_id x from public.characters where cloth_id is not null
                             union all select user_id, amulet_id from public.characters where amulet_id is not null) t
  on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
update public.characters set cloth_id = null, amulet_id = null where cloth_id is not null or amulet_id is not null;
-- veículos: todos comuns, sem reforma em andamento
update public.vehicles set rarity = 'common', refurb_rarity = null, refurb_until = null
  where rarity <> 'common' or refurb_rarity is not null or refurb_until is not null;

create or replace function public.pet_def(p_pet text)
returns jsonb language sql stable set search_path = '' as $$
  select x from jsonb_array_elements(public.config_get('characters') -> 'pets' -> 'list') x where x ->> 'id' = p_pet
$$;

-- nível do pet pela afinidade (1 a 5) e fator do efeito (40% no 1 a 100% no 5); 0 se a fazenda não tem o pet
create or replace function public.pet_level(p_user uuid, p_pet text)
returns int language sql stable set search_path = '' as $$
  select coalesce((select 1 + (select count(*) from jsonb_array_elements_text(public.config_get('characters') -> 'pets' -> 'affinity_to_level') a
                              where a::int <= p.affinity)::int
                   from public.pets p where p.user_id = p_user and p.pet_id = p_pet), 0)
$$;

create or replace function public.pet_factor(p_user uuid, p_pet text)
returns double precision language sql stable set search_path = '' as $$
  with c as (select public.config_get('characters') -> 'pets' c), l as (select public.pet_level(p_user, p_pet) lv)
  select case when lv = 0 then 0 else (c ->> 'effect_at_level_1')::double precision
           + ((c ->> 'effect_at_level_5')::double precision - (c ->> 'effect_at_level_1')::double precision) * (lv - 1) / 4.0 end
  from c, l
$$;

-- compatibilidade: o resumo dos pets (o vínculo acabou)
create or replace function public.pet_info(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when count(*) = 0 then null else jsonb_build_object('level', max(public.pet_level(p_user, p.pet_id)), 'count', count(*)) end
  from public.pets p where p.user_id = p_user
$$;

-- os pets chegam sozinhos no nível de cada um; a contagem do achado começa na chegada
create or replace function public.pets_unlock(p_user uuid, p_time double precision)
returns void language plpgsql security definer set search_path = '' as $$
declare v_level int; x jsonb;
begin
  select level into v_level from public.farms where user_id = p_user;
  for x in select value from jsonb_array_elements(public.config_get('characters') -> 'pets' -> 'list') loop
    if (x ->> 'unlock_level')::int <= v_level then
      insert into public.pets (user_id, pet_id, active, find_t) values (p_user, x ->> 'id', true, p_time)
        on conflict (user_id, pet_id) do nothing;
    end if;
  end loop;
end;
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
  -- pets (v3): os três valem ao mesmo tempo, cada um pelo próprio nível
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    gato := coalesce((public.pet_def('gato') ->> 'energy_recovery_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'gato');
    gato_animal := coalesce((public.pet_def('gato') ->> 'animal_production_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'gato');
    dog_pts := coalesce((public.pet_def('cachorro') ->> 'expedition_success_pts')::double precision, 0) * public.pet_factor(p_user, 'cachorro');
    dog_rec := coalesce((public.pet_def('cachorro') ->> 'lost_cargo_recovery_chance')::double precision, 0) * public.pet_factor(p_user, 'cachorro');
    papagaio := coalesce((public.pet_def('papagaio') ->> 'sales_gold_pct')::double precision, 0) / 100 * public.pet_factor(p_user, 'papagaio');
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
  perform public.pets_unlock(p_user, t1);
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
end;
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
      'cloth_id', ch.cloth_id, 'amulet_id', ch.amulet_id, 'material', coalesce(t.material, 'wood'), 'durability', round(coalesce(t.durability, 100)::numeric, 2),
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

-- carinho: 1 por dia por pet; sobe a afinidade (o nível)
create or replace function public.care_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_day date := public.game_day(now()); p public.pets;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into p from public.pets where user_id = v_user and pet_id = p_pet for update;
  if not found then raise exception 'pet ainda não chegou' using errcode = 'check_violation'; end if;
  if p.last_care = v_day then raise exception 'carinho de hoje já foi dado' using errcode = 'check_violation'; end if;
  update public.pets set affinity = affinity + 1, last_care = v_day where user_id = v_user and pet_id = p_pet;
  return public.farm_state(v_user);
end;
$$;

-- achado do pet: pronto depois de find_hours (relógio da fazenda); o clique recolhe e a contagem recomeça
create or replace function public.collect_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); p public.pets; d jsonb; f public.farms; fac double precision; lv int;
  v_gold numeric := 0; v_energy double precision := 0; v_card bigint; v_card_row public.cards; c public.characters; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into p from public.pets where user_id = v_user and pet_id = p_pet for update;
  if not found then raise exception 'pet ainda não chegou' using errcode = 'check_violation'; end if;
  select * into f from public.farms where user_id = v_user;
  d := public.pet_def(p_pet);
  if f.farm_time < coalesce(p.find_t, f.farm_time) + (d ->> 'find_hours')::double precision * 3600 then
    raise exception 'o achado ainda não está pronto' using errcode = 'check_violation';
  end if;
  fac := public.pet_factor(v_user, p_pet); lv := public.pet_level(v_user, p_pet);
  if d -> 'find' ? 'gold_share_of_R' then
    v_gold := round(public.ref_income(f.level) * (d -> 'find' ->> 'gold_share_of_R')::numeric * fac::numeric, 2);
    if v_gold > 0 then
      perform public.ledger_post(v_user, v_gold, 'pet_find', jsonb_build_object('pet', p_pet, 'level', lv), 'pet:' || p_pet || ':' || round(p.find_t)::text);
      perform public.mission_progress(v_user, 'gold_earned', v_gold);
    end if;
  end if;
  if d -> 'find' ? 'card_chance' and public.rand01() < (d -> 'find' ->> 'card_chance')::double precision
                                                      + (d -> 'find' ->> 'card_chance_per_level')::double precision * (lv - 1) then
    v_card := public.draw_card(v_user, 'pet');
    select * into v_card_row from public.cards where serial = v_card;
  end if;
  if d -> 'find' ? 'team_energy' then
    v_energy := (d -> 'find' ->> 'team_energy')::double precision * fac;
    fx := public.team_fx(v_user);
    for c in select * from public.characters where user_id = v_user for update loop
      update public.characters set energy = least((public.char_energy(c, fx) ->> 'max')::double precision, energy + v_energy),
          parked = case when energy + v_energy >= (public.config_get('characters') -> 'energy' ->> 'parked_until')::double precision then false else parked end
        where user_id = v_user and class_id = c.class_id;
    end loop;
  end if;
  update public.pets set find_t = f.farm_time where user_id = v_user and pet_id = p_pet;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'pet.find', v_user, jsonb_build_object('pet', p_pet, 'level', lv, 'gold', v_gold, 'energy', v_energy, 'card', v_card));
  return public.farm_state(v_user) || jsonb_build_object('pet_find', jsonb_build_object('pet', p_pet, 'gold', v_gold, 'energy', round(v_energy::numeric, 1),
    'card', case when v_card is null then null else jsonb_build_object('serial', v_card, 'card_id', v_card_row.card_id, 'rarity', v_card_row.rarity) end));
end;
$$;

create or replace function public.adopt_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'os pets agora chegam sozinhos' using errcode = 'check_violation';
end;
$$;

create or replace function public.set_active_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'os pets agora ficam todos juntos na fazenda' using errcode = 'check_violation';
end;
$$;

create or replace function public.link_pet(p_class text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'os pets não se vinculam mais a personagens' using errcode = 'check_violation';
end;
$$;

create or replace function public.refurbish_vehicle(p_vehicle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'a reforma de veículos acabou' using errcode = 'check_violation';
end;
$$;

create or replace function public.equip_item(p_class text, p_slot text, p_item text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'os itens de funcionário acabaram' using errcode = 'check_violation';
end;
$$;

create or replace function public.exp_resolve(p_id uuid, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; e jsonb := public.config_get('expeditions'); r jsonb; lead jsonb; u double precision; pc double precision;
  v_out text; v_gold numeric := 0; v_refund numeric := 0; v_loss double precision; v_back jsonb := '{}'; v_drops jsonb := '[]';
  v_rolls int := 1; k int; c record; v_lost int; v_rec boolean := false; v_txt text;
begin
  select * into x from public.expeditions where id = p_id for update;
  r := public.exp_route(x.route_id);
  if x.led then lead := public.lead_info(x.user_id); end if;
  u := public.rand01();
  -- crítico: base + Gerente + Estrada Livre/Trevo/Armory gravados na saída (teto absoluto da GDD)
  pc := least(x.chance, coalesce((public.config_get('cards') -> 'bonus_caps' -> 'expedition_crit_pct' ->> 'absolute')::double precision, 60) / 100,
              (e -> 'crit' ->> 'chance')::double precision + (coalesce((lead ->> 'crit_pts')::double precision, 0) + public.jnum(x.card_fx, 'crit_pts')) / 100);
  if u < pc then v_out := 'crit'; elsif u < x.chance then v_out := 'success'; else v_out := 'fail'; end if;

  if v_out = 'crit' then
    v_gold := round(x.cargo_value * (1 + (e -> 'crit' ->> 'bonus_value')::numeric * (1 + public.jnum(x.card_fx, 'crit_val')::numeric / 100)) * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
    v_rolls := (e -> 'crit' ->> 'card_rolls')::int;
  elsif v_out = 'success' then
    v_gold := round(x.cargo_value * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
  else
    v_loss := ((r -> 'loss' ->> 0)::double precision + public.rand01() * ((r -> 'loss' ->> 1)::double precision - (r -> 'loss' ->> 0)::double precision))
              * (1 + coalesce((lead ->> 'loss_pct')::double precision, 0) / 100);
    v_loss := greatest(0, least(1, v_loss)) * (1 - least(100, public.jnum(x.card_fx, 'loss_red')) / 100);  -- Estrada Livre
    -- o Cachorro pode farejar a carga perdida
    if public.rand01() < coalesce((fx ->> 'dog_recover')::double precision, 0) then v_rec := true; v_loss := 0; end if;
    for c in select key, value::int q from jsonb_each_text(x.cargo) loop
      v_lost := round(c.q * v_loss)::int;
      v_back := v_back || jsonb_build_object(c.key, c.q - v_lost);
    end loop;
    if x.insurance > 0 then
      v_refund := round(greatest(0, v_loss - (e ->> 'insurance_deductible')::double precision)::numeric * x.cargo_value, 2);
    end if;
  end if;

  if v_gold > 0 then v_gold := round(v_gold * (1 + public.jnum(x.card_fx, 'profit')::numeric / 100), 2); end if;  -- carta de Veículo
  if v_gold > 0 then v_gold := v_gold + public.moon_bonus(x.user_id, v_gold, fx); end if;
  -- missões: ouro ganho e viagem longe com sucesso
  perform public.mission_progress(x.user_id, 'gold_earned', v_gold);
  if v_out <> 'fail' and public.exp_route_idx(x.route_id) >= public.exp_route_idx(public.config_get('missions') ->> 'far_route') then
    perform public.mission_progress(x.user_id, 'exp_far_success', 1);
  end if;

  -- prêmio (v3): chance de carta (sorteada ao Receber); o crítico rola mais vezes; Gerente e Ferradura aumentam a chance
  for k in 1 .. v_rolls loop
    if public.rand01() < (r ->> 'card_chance')::double precision * (1 + coalesce((lead ->> 'item_pct')::double precision, 0) / 100) * (1 + public.jnum(x.card_fx, 'item_boost') / 100) then
      v_drops := v_drops || to_jsonb('card'::text);
    end if;
  end loop;

  v_txt := (e -> 'reports' -> v_out) ->> floor(public.rand01() * jsonb_array_length(e -> 'reports' -> v_out))::int;
  v_txt := replace(replace(v_txt, '{route}', r ->> 'name_pt'), '{lost}', round(coalesce(v_loss, 0) * 100)::text || '%');
  if v_rec then v_txt := v_txt || ' ' || (e -> 'reports' ->> 'recovered'); end if;

  update public.expeditions set status = 'back', outcome = v_out, loss_frac = v_loss, gold = v_gold, refund = v_refund,
      cargo_back = v_back, drops = v_drops, report = v_txt
    where id = p_id;
  update public.farms set exp_fail_streak = case when v_out = 'fail' then exp_fail_streak + 1 else 0 end where user_id = x.user_id;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (x.user_id, 'expedition.back', x.user_id, jsonb_build_object('id', x.id, 'route', x.route_id, 'vehicle', x.vehicle_id,
      'outcome', v_out, 'chance', round(x.chance::numeric, 4), 'roll', round(u::numeric, 6), 'gold', v_gold, 'refund', v_refund, 'drops', v_drops));
end;
$function$;

create or replace function public.collect_expeditions(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); x public.expeditions; d text; v_list jsonb := '[]'; v_cards jsonb; v_serial bigint; cr public.cards;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  for x in select * from public.expeditions where user_id = v_user and status = 'back' and (p_vehicle is null or vehicle_id = p_vehicle)
           order by returns_at for update loop
    if x.gold > 0 then
      perform public.ledger_post(v_user, x.gold, 'exp_sale', jsonb_build_object('id', x.id, 'route', x.route_id, 'outcome', x.outcome), 'exp:' || x.id);
    end if;
    if x.refund > 0 then
      perform public.ledger_post(v_user, x.refund, 'exp_insurance_refund', jsonb_build_object('id', x.id, 'route', x.route_id), 'expref:' || x.id);
    end if;
    perform public.silo_add(v_user, x.cargo_back);
    -- achados: carta (v3) sorteada agora; achados antigos (itens, Kits, Escrituras) ainda entram no inventário
    v_cards := '[]';
    for d in select jsonb_array_elements_text(x.drops) loop
      if d = 'card' then
        v_serial := public.draw_card(v_user, 'expedition');
        select * into cr from public.cards where serial = v_serial;
        v_cards := v_cards || jsonb_build_array(jsonb_build_object('serial', v_serial, 'card_id', cr.card_id, 'rarity', cr.rarity));
      else
        insert into public.inventory (user_id, item_id, qty) values (v_user, d, 1)
          on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
      end if;
    end loop;
    update public.expeditions set status = 'collected', collected_at = now() where id = x.id;
    v_list := v_list || jsonb_build_object('id', x.id, 'vehicle_id', x.vehicle_id, 'route_id', x.route_id, 'seq', x.seq, 'outcome', x.outcome,
      'gold', x.gold, 'refund', x.refund, 'cargo', x.cargo, 'cargo_back', x.cargo_back, 'loss_frac', x.loss_frac, 'drops', x.drops, 'cards', v_cards,
      'report', x.report, 'insurance', x.insurance, 'minigame', x.minigame, 'chance', round(x.chance::numeric, 4));
  end loop;
  if v_list = '[]'::jsonb then raise exception 'nada para receber' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user) || jsonb_build_object('collected', v_list);
end;
$$;

create or replace function public.mission_progress(p_user uuid, p_metric text, p_amount numeric)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  at timestamptz := public.fx_at(); d date; w date; m public.missions; cfg jsonb := public.config_get('missions'); wk public.mission_weeks; n int;
begin
  if coalesce(p_amount, 0) <= 0 then return; end if;
  -- testes antigos (fases 0–6) desligam as missões para os prêmios não mudarem as contas deles
  if current_setting('vif.missions', true) = 'off' then return; end if;
  d := public.user_day(p_user, at); w := public.mission_week(d);
  perform public.mission_ensure(p_user, at);
  for m in update public.missions set progress = least(target, progress + p_amount),
               done_at = case when progress + p_amount >= target then at else null end
           where user_id = p_user and metric = p_metric and done_at is null
             and ((kind = 'daily' and period = d) or (kind = 'weekly' and period = w))
           returning * loop
    continue when m.done_at is null;
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'mission.done', p_user, jsonb_build_object('kind', m.kind, 'id', m.mission_id, 'period', m.period));
    if m.kind = 'daily' then
      if (m.reward ->> 'gold')::numeric > 0 then
        -- Comerciante (ramo Negócios): +5% por ponto no ouro das missões, com ele em campo
        perform public.ledger_post(p_user, round((m.reward ->> 'gold')::numeric * (1 + coalesce((select sum(public.skill_effect(ch.class_id, ch.skills, 'mission_gold_pct'))
            from public.characters ch where ch.user_id = p_user and public.char_active(ch)), 0)::numeric / 100), 2),
          'mission', jsonb_build_object('id', m.mission_id, 'period', m.period),
          'mission:' || m.kind || ':' || m.period || ':' || m.slot);
      end if;
      perform public.add_xp(p_user, (m.reward ->> 'xp')::numeric);
      -- as 5 do dia: 1 pacote (até o limite da semana); 2 cartas do nível 15 em diante
      if not exists (select 1 from public.missions where user_id = p_user and kind = 'daily' and period = d and done_at is null)
         and (select daily_pack_day from public.farms where user_id = p_user) is distinct from d then
        select * into wk from public.mission_weeks where user_id = p_user and week = w for update;
        if wk.daily_packs < (cfg -> 'daily' ->> 'max_packs_per_week')::int then
          update public.mission_weeks set daily_packs = daily_packs + 1 where user_id = p_user and week = w;
          update public.farms set daily_pack_day = d where user_id = p_user;
          for n in 1 .. public.daily_pack_cards(p_user) loop perform public.draw_card(p_user, 'daily_pack'); end loop;
        end if;
      end if;
    else
      select count(*) into n from public.missions where user_id = p_user and kind = 'weekly' and period = w and done_at is not null;
      select * into wk from public.mission_weeks where user_id = p_user and week = w for update;
      if n >= 3 and wk.weekly_rewards < 1 then
        update public.mission_weeks set weekly_rewards = 1 where user_id = p_user and week = w;
        perform public.draw_card(p_user, 'weekly_3');
      end if;
      if n >= (cfg -> 'weekly' ->> 'count')::int and wk.weekly_rewards < 2 then
        update public.mission_weeks set weekly_rewards = 2 where user_id = p_user and week = w;
        perform public.draw_card(p_user, 'weekly_5');
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.pet_def(text), public.pet_level(uuid, text), public.pet_factor(uuid, text), public.pets_unlock(uuid, double precision) from public, anon, authenticated;
revoke all on function public.collect_pet(text) from public, anon;
grant execute on function public.collect_pet(text) to authenticated;
