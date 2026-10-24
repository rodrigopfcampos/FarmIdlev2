-- Fase 4: animais. Galinheiro e Celeiro com vagas (4 → 8 → 12, ampliação na Forja de preços da config),
-- Lago (+10% nas aves e +2 vagas só para aves), 10 animais com raridade sorteada na compra, ração cobrada no
-- começo de cada ciclo (sem ouro: com fome, para e volta quando entra ouro), coleta igual à lavoura (clique
-- grátis; fora do jogo a equipe coleta na fila, 100% com a Rancheira em campo e 60% sem ela).
-- Também: efeitos de habilidade da fase 4 (Criação da Rancheira, Mestria de Obras), Gato +10% na produção
-- animal e os tetos de bônus da seção 11 (config cards.bonus_caps).

create table public.animal_houses (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  house_id text not null,                 -- galinheiro, celeiro
  tier integer not null default 0 check (tier >= 0),
  primary key (user_id, house_id)
);

create table public.animals (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  house_id text not null,
  slot integer not null check (slot >= 1),
  animal_id text not null,
  rarity text not null,                   -- sorteada na compra, fixa
  state text not null default 'growing' check (state in ('growing', 'hungry')),
  cycle_start double precision,           -- tempo da fazenda
  ready_at double precision,              -- produto pronto (espera o clique ou a equipe)
  bought_at timestamptz not null default now(),
  primary key (user_id, house_id, slot)
);

alter table public.animal_houses enable row level security;
alter table public.animals enable row level security;
create policy animal_houses_read_own on public.animal_houses for select to authenticated using (user_id = (select auth.uid()));
create policy animals_read_own on public.animals for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.animal_houses, public.animals from anon, authenticated;

-- ---------- ajudantes ----------
create or replace function public.animal_def(p_animal text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('animals') -> 'animals') x where x ->> 'id' = p_animal
$$;

-- preço da Feira de um item do Silo: cultivo, fruta ou produto animal
create or replace function public.item_price(p_item text)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce((public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric,
    (select (x -> 'product' ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('animals') -> 'animals') x
     where x -> 'product' ->> 'id' = p_item limit 1))
$$;

-- lote do mapa de cada casa (pelo tipo do lote)
create or replace function public.house_lot(p_house text)
returns text
language sql stable
set search_path = ''
as $$
  select x ->> 'id' from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x
  where x ->> 'type' = public.config_get('animals') -> 'houses' -> p_house ->> 'lot_type' limit 1
$$;

-- a casa existe quando o pasto é seu e a limpeza acabou
create or replace function public.house_ready(p_user uuid, p_house text, p_t double precision)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from public.owned_lots ol where ol.user_id = p_user and ol.lot_id = public.house_lot(p_house) and ol.ready_at <= p_t)
$$;

create or replace function public.lake_ready(p_user uuid, p_t double precision)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from public.owned_lots ol
                 join lateral (select x from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = ol.lot_id) d on true
                 where ol.user_id = p_user and d.x ->> 'type' = 'pasto_lago' and ol.ready_at <= p_t)
$$;

-- vagas da casa no nível de ampliação atual (sem as vagas do Lago)
create or replace function public.house_slots(p_user uuid, p_house text)
returns int
language sql stable
set search_path = ''
as $$
  select (public.config_get('animals') -> 'houses' -> p_house -> 'slots'
          -> coalesce((select tier from public.animal_houses where user_id = p_user and house_id = p_house), 0) ->> 'slots')::int
$$;

-- vagas extras só para aves (Galinheiro com o Lago)
create or replace function public.house_bird_slots(p_user uuid, p_house text, p_t double precision)
returns int
language sql stable
set search_path = ''
as $$
  select case when p_house = 'galinheiro' and public.lake_ready(p_user, p_t)
              then coalesce((public.config_get('animals') -> 'rules' -> 'lake_bonus' ->> 'extra_galinheiro_slots')::int, 0) else 0 end
$$;

-- começa um ciclo: cobra a ração do ciclo se couber em p_gold_left; senão o animal fica com fome.
-- Devolve o custo da ração (o chamador lança no ledger) ou null quando ficou com fome.
create or replace function public.animal_start(p_user uuid, p_house text, p_slot int, p_t double precision, fx jsonb, p_gold_left numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare a public.animals; d jsonb; v_cost numeric;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  if not found then return null; end if;
  d := public.animal_def(a.animal_id);
  v_cost := round((d ->> 'feed_cost_per_day')::numeric * (d ->> 'produce_every_minutes')::numeric / 1440
                  * (1 - coalesce((fx ->> 'feed_discount')::numeric, 0)), 2);
  if coalesce(p_gold_left, 0) < v_cost then
    update public.animals set state = 'hungry', cycle_start = p_t, ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
    return null;
  end if;
  update public.animals set state = 'growing', cycle_start = p_t, ready_at = p_t + (d ->> 'produce_every_minutes')::double precision * 60
    where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_cost;
end;
$$;

-- coleta o produto: raridade × (1 + bônus, com teto), Lago nas aves, produto duplo; a equipe sem Rancheira rende 60%
create or replace function public.animal_collect(p_user uuid, p_house text, p_slot int, p_t double precision, fx jsonb, p_team boolean)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare a public.animals; d jsonb; r jsonb := public.config_get('animals') -> 'rules'; m double precision; bonus double precision; v_qty int;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  d := public.animal_def(a.animal_id);
  bonus := coalesce((fx ->> 'animal_production')::double precision, 0)
         + case when (d ->> 'is_bird')::boolean and public.lake_ready(p_user, p_t) then (r -> 'lake_bonus' ->> 'bird_production')::double precision else 0 end;
  m := public.rarity_mult(a.rarity) * (1 + least(bonus, coalesce((fx ->> 'animal_cap')::double precision, 0.6)))
     * case when p_team then case when coalesce((fx ->> 'rancheira')::boolean, false) then (r -> 'collector_efficiency' ->> 'rancheira')::double precision
                                  else (r -> 'collector_efficiency' ->> 'other_class')::double precision end else 1 end;
  if public.rand01() < coalesce((fx ->> 'animal_double')::double precision, 0) then m := m * 2; end if;
  v_qty := public.round_rand(coalesce((r ->> 'units_per_collect')::double precision, 1) * m);
  if v_qty > 0 then
    insert into public.silo (user_id, item_id, qty) values (p_user, d -> 'product' ->> 'id', v_qty)
      on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  end if;
  perform public.add_xp(p_user, round((d ->> 'xp_per_collect')::numeric * (1 + (fx ->> 'account_xp')::numeric), 2));
  update public.animals set ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_qty;
end;
$$;

-- animais com fome voltam quando há ouro (sem gastar trabalho); devolve a ração cobrada (ledger por conta do chamador)
create or replace function public.animals_feed_hungry(p_user uuid, p_t double precision, fx jsonb, p_gold numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare r record; v_total numeric := 0; v_c numeric;
begin
  for r in select house_id, slot from public.animals where user_id = p_user and state = 'hungry' order by house_id, slot loop
    v_c := public.animal_start(p_user, r.house_id, r.slot, p_t, fx, p_gold - v_total);
    exit when v_c is null;
    v_total := v_total + v_c;
  end loop;
  return v_total;
end;
$$;



-- volta a alimentar quem está com fome agora (depois de uma venda); lança a ração no ledger
create or replace function public.feed_hungry_now(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_time double precision; v_gold numeric; v_c numeric;
begin
  if not exists (select 1 from public.animals where user_id = p_user and state = 'hungry') then return; end if;
  select farm_time into v_time from public.farms where user_id = p_user;
  select gold into v_gold from public.wallets where user_id = p_user;
  v_c := public.animals_feed_hungry(p_user, v_time, public.team_fx(p_user), v_gold);
  if v_c > 0 then perform public.ledger_post(p_user, -round(v_c, 2), 'feed', jsonb_build_object('restart', true)); end if;
end;
$$;

-- ---------- efeitos da equipe (fase 4: animais e tetos de bônus) ----------
create or replace function public.team_fx(p_user uuid)
returns jsonb
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  cfg jsonb := public.config_get('characters');
  fe jsonb := cfg -> 'field_effects';
  crops jsonb := public.config_get('crops') -> 'rules';
  base_stall double precision := coalesce((public.config_get('expeditions') ->> 'stall_price_ratio')::double precision, 0.7);
  v_effects text[] := array['crop_growth_pct', 'growth_all_pct', 'orchard_speed_pct', 'tree_initial_time_pct', 'double_harvest_crop_pct',
    'golden_pct', 'harvest_xp_pct', 'seed_cost_pct', 'shop_discount_pct', 'cleanup_time_pct', 'tool_cost_pct', 'team_capacity_pct',
    'tool_effect_pct', 'stall_price_pts', 'daily_boosted_sale', 'sales_gold_pct', 'recurring_production_pct', 'account_xp_pct',
    'orchard_extra_fruit_chance', 'early_unlock_levels', 'animal_production_pct', 'feed_cost_pct', 'animal_double_pct',
    'expansion_cost_pct'];
  caps jsonb := coalesce(public.config_get('cards') -> 'bonus_caps', '{}'::jsonb);
  cap_seed double precision := coalesce((caps -> 'seed_sapling_feed_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100;
  ranch boolean := false;
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0; gato_animal double precision := 0;
begin
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
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    if pet ->> 'id' = 'gato' then
      gato := (select (x ->> 'energy_recovery_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
      gato_animal := (select (x ->> 'animal_production_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'papagaio' then
      papagaio := (select (x ->> 'sales_gold_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio') / 100 * (pet ->> 'factor')::double precision;
    end if;
  end if;
  return jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100),
    'golden', least((crops -> 'golden_harvest' ->> 'cap_permanent')::double precision, (s ->> 'golden_pct')::double precision / 100),
    'golden_mult', (crops -> 'golden_harvest' ->> 'multiplier')::double precision,
    'harvest_xp', ((s ->> 'harvest_xp_pct')::double precision + case when bot then (fe -> 'botanica' ->> 'harvest_xp_pct')::double precision else 0 end) / 100,
    'account_xp', least(coalesce((caps -> 'account_xp_pct' ->> 'permanent')::double precision, 100) / 100, (s ->> 'account_xp_pct')::double precision / 100),
    'recurring', (s ->> 'recurring_production_pct')::double precision / 100,
    'extra_fruit', (s ->> 'orchard_extra_fruit_chance')::double precision,
    'seed_discount', least(cap_seed, (-(s ->> 'seed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'seed_discount_pct_per_material')::double precision * (com + 1) else 0 end) / 100),
    'shop_discount', least(cap_seed, -(s ->> 'shop_discount_pct')::double precision / 100),
    'feed_discount', least(cap_seed, (-(s ->> 'feed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision) / 100),
    'animal_production', ((s ->> 'animal_production_pct')::double precision) / 100 + gato_animal,
    'animal_cap', coalesce((caps -> 'animal_production_pct' ->> 'permanent')::double precision, 60) / 100,
    'animal_double', (s ->> 'animal_double_pct')::double precision / 100,
    'expansion_cost', (s ->> 'expansion_cost_pct')::double precision / 100,
    'rancheira', ranch,
    'stall_ratio', least((fe -> 'comerciante' ->> 'stall_price_cap')::double precision,
                   base_stall + ((s ->> 'stall_price_pts')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'stall_price_pts_per_material')::double precision * (com + 1) else 0 end) / 100),
    'sales_gold', least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100, (s ->> 'sales_gold_pct')::double precision / 100 + papagaio),
    'daily_boost', (s ->> 'daily_boosted_sale')::double precision,
    'cleanup', (s ->> 'cleanup_time_pct')::double precision / 100,
    'tool_cost', (s ->> 'tool_cost_pct')::double precision / 100,
    'team_capacity', (s ->> 'team_capacity_pct')::double precision / 100,
    'tool_effect', (s ->> 'tool_effect_pct')::double precision / 100,
    'gerente_cut', case when ger >= 0 then ((fe -> 'gerente' ->> 'team_energy_use_pct_base')::double precision
                     + (fe -> 'gerente' ->> 'team_energy_use_pct_per_material')::double precision * ger) / 100 else 0 end,
    'auto_sell', com >= 0,
    'auto_pay', ger >= 0,
    'rare_seed', case when bot then (fe -> 'botanica' ->> 'rare_seed_chance')::double precision else 0 end + pet_rare,
    'seed_refund', case when bot then (fe -> 'botanica' ->> 'seed_refund_chance')::double precision else 0 end,
    'early_unlock', case when (s ->> 'early_unlock_levels')::double precision > 0 and bot_choice is not null
                     then jsonb_build_object('crop', bot_choice, 'levels', (s ->> 'early_unlock_levels')::int) end,
    'gato_rest', gato,
    'pet', pet);
end;
$$;

create or replace function public.char_energy(c public.characters, fx jsonb)
returns jsonb
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy'),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + public.skill_effect(c.class_id, c.skills, 'energy_use_pct') / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 - (ch -> 'pets' ->> 'per_level_energy_use_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') / 100)))
  from cfg
$$;

-- ---------- avanço da fazenda (fase 4: coleta dos animais na fila e ração por ciclo) ----------
create or replace function public.advance_farm(p_user uuid, p_now timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
  e record; lt double precision; te double precision;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  labor := f.labor_bank;
  seg0 := t0;

  while seg0 < t1 loop
    seg1 := least(t1, seg0 + v_step);
    -- salário das meias-noites até o fim deste passo (no relógio real)
    perform public.process_payday(p_user, f.synced_at + make_interval(secs => seg1 - t0));
    fx := public.team_fx(p_user);
    if (fx ->> 'auto_pay')::boolean then perform public.pay_debts(p_user); end if;
    perform public.rotate_team(p_user);
    fx := public.team_fx(p_user);
    tr := public.team_rate(p_user, fx);
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
        select 'harvest'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, v_harvest_cost as cost
          from public.plots pl
          where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= seg1
        union all
        select 'harvest_tree', t.lot_id, t.slot, t.ready_at, v_harvest_cost
          from public.trees t
          where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= seg1
        union all
        select 'collect', a.house_id, a.slot, a.ready_at, v_harvest_cost
          from public.animals a
          where a.user_id = p_user and a.state = 'growing' and a.ready_at <= seg1
        union all
        select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost
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
    if public.auto_sell(p_user, fx) > 0 then
      update public.plots set stalled_reason = null, free_since = seg1 where user_id = p_user and stalled_reason = 'sem_ouro';
    end if;
    seg0 := seg1;
  end loop;

  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
end;
$$;

create or replace function public.tend_plots(p_user uuid, p_target text, p_harvest boolean, p_plant boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_time double precision; fx jsonb := public.team_fx(p_user);
  v_gold numeric; v_seed_spent numeric := 0; v_refund numeric := 0; v_plantings int := 0; v_seed numeric; v_feed numeric := 0; v_f numeric;
  r record;
begin
  select farm_time into v_time from public.farms where user_id = p_user for update;
  if p_harvest then
    for r in select pl.plot_id from public.plots pl
             where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      v_refund := v_refund + public.harvest_plot(p_user, r.plot_id, v_time, fx);
    end loop;
    for r in select t.lot_id, t.slot from public.trees t
             where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= v_time
               and (p_target is null or t.lot_id = p_target)
             order by t.lot_id, t.slot loop
      perform public.harvest_tree(p_user, r.lot_id, r.slot, v_time, fx);
    end loop;
    if v_refund > 0 then perform public.ledger_post(p_user, round(v_refund, 2), 'seed_refund', jsonb_build_object('by', 'player')); end if;
    -- animais prontos: o clique coleta a 100% e começa o próximo ciclo (cobra a ração)
    select gold into v_gold from public.wallets where user_id = p_user;
    for r in select a.house_id, a.slot from public.animals a
             where a.user_id = p_user and a.state = 'growing' and a.ready_at <= v_time
               and (p_target is null or p_target = public.house_lot(a.house_id))
             order by a.house_id, a.slot loop
      perform public.animal_collect(p_user, r.house_id, r.slot, v_time, fx, false);
      v_f := public.animal_start(p_user, r.house_id, r.slot, v_time, fx, v_gold - v_feed);
      v_feed := v_feed + coalesce(v_f, 0);
    end loop;
    if v_feed > 0 then perform public.ledger_post(p_user, -round(v_feed, 2), 'feed', jsonb_build_object('by', 'player')); end if;
  end if;
  if p_plant then
    select gold into v_gold from public.wallets where user_id = p_user for update;
    for r in select pl.plot_id, pl.crop_id from public.plots pl
             join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
             where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and ol.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      v_seed := public.seed_price(r.crop_id, fx);
      if v_gold - v_seed_spent < v_seed then
        update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = r.plot_id;
        continue;
      end if;
      v_seed_spent := v_seed_spent + public.plant_plot(p_user, r.plot_id, r.crop_id, v_time, fx);
      v_plantings := v_plantings + 1;
    end loop;
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds',
        jsonb_build_object('plantings', v_plantings, 'farm_time', round(v_time::numeric, 1), 'by', 'player'));
    end if;
  end if;
end;
$$;

create or replace function public.farm_state(p_user uuid)
returns jsonb
language plpgsql stable
security definer
set search_path = ''
as $$
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
      'energy_rest', round((public.char_energy(ch, fx) ->> 'rest')::numeric, 3), 'active', public.char_active(ch),
      'salary', public.salary_of(p_user, ch)) order by ch.hired_at), '[]')
    into v_chars
    from public.characters ch left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
    where ch.user_id = p_user;
  select coalesce(jsonb_object_agg(x ->> 'id', round(public.ref_income(v_level) * (x ->> 'price_R_ratio')::numeric * (1 - (fx ->> 'shop_discount')::numeric), 2)), '{}')
    into v_snacks from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x;
  select jsonb_build_object(
    'server_now', now(),
    'game_day', public.game_day(now()),
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
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p.pet_id, 'affinity', p.affinity, 'last_care', p.last_care,
        'active', p.active, 'linked_class', p.linked_class) order by p.adopted_at), '[]') from public.pets p where p.user_id = p_user),
    'pet', fx -> 'pet',
    'snack_prices', v_snacks,
    'fx', jsonb_build_object('stall_ratio', fx -> 'stall_ratio', 'seed_discount', fx -> 'seed_discount', 'sales_gold', fx -> 'sales_gold',
        'shop_discount', fx -> 'shop_discount', 'auto_sell', fx -> 'auto_sell', 'auto_pay', fx -> 'auto_pay', 'rare_seed', fx -> 'rare_seed',
        'seed_refund', fx -> 'seed_refund', 'gerente_cut', fx -> 'gerente_cut', 'early_unlock', fx -> 'early_unlock', 'daily_boost', fx -> 'daily_boost',
        'growth_crop', fx -> 'growth_crop', 'growth_orchard', fx -> 'growth_orchard', 'tree_initial', fx -> 'tree_initial', 'cleanup', fx -> 'cleanup',
        'tool_cost', fx -> 'tool_cost', 'harvest_xp', fx -> 'harvest_xp', 'golden', fx -> 'golden',
        'feed_discount', fx -> 'feed_discount', 'animal_production', fx -> 'animal_production', 'animal_cap', fx -> 'animal_cap',
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base;
end;
$$;

-- ---------- vendas: cultivo, fruta ou produto animal ----------
create or replace function public.auto_sell(p_user uuid, fx jsonb)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare r record; v_total numeric := 0; v_items jsonb := '{}'::jsonb; v_price numeric;
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
    perform public.ledger_post(p_user, v_total, 'auto_sale', jsonb_build_object('items', v_items, 'ratio', fx -> 'stall_ratio'));
  end if;
  return v_total;
end;
$$;

create or replace function public.sell_at_stall(p_item text, p_qty int, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  fx jsonb; v_price numeric; v_have int; v_amount numeric; v_time double precision; v_boost numeric := 1; v_day date := public.game_day(now());
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'chave de idempotência obrigatória' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.ledger where user_id = v_user and idempotency_key = p_idempotency_key) then
    return public.farm_state(v_user);
  end if;
  v_price := public.item_price(p_item);
  if v_price is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
  if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  fx := public.team_fx(v_user);
  if (fx ->> 'daily_boost')::numeric > 1 and (select boosted_sale_day from public.farms where user_id = v_user) is distinct from v_day then
    v_boost := (fx ->> 'daily_boost')::numeric;
    update public.farms set boosted_sale_day = v_day where user_id = v_user;
  end if;
  update public.silo set qty = qty - p_qty where user_id = v_user and item_id = p_item;
  v_amount := round(p_qty * v_price * (fx ->> 'stall_ratio')::numeric * (1 + (fx ->> 'sales_gold')::numeric) * v_boost, 2);
  perform public.ledger_post(v_user, v_amount, 'stall_sale', jsonb_build_object('item', p_item, 'qty', p_qty, 'price', v_price,
    'ratio', fx -> 'stall_ratio', 'sales_gold', fx -> 'sales_gold', 'boost', v_boost), p_idempotency_key);
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots set stalled_reason = null, free_since = v_time where user_id = v_user and stalled_reason = 'sem_ouro';
  perform public.advance_farm(v_user, now());
  perform public.feed_hungry_now(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.set_auto_sell(p_item text, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.item_price(p_item) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  insert into public.silo (user_id, item_id, qty, auto_sell) values (v_user, p_item, 0, coalesce(p_on, false))
    on conflict (user_id, item_id) do update set auto_sell = coalesce(p_on, false);
  return public.farm_state(v_user);
end;
$$;

-- ---------- ações do jogo ----------
-- comprar um animal para uma vaga: raridade sorteada no servidor (fixa) e o 1º ciclo começa na hora
create or replace function public.buy_animal(p_house text, p_slot int, p_animal text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); d jsonb := public.animal_def(p_animal); v_time double precision; v_level int;
  v_base int; v_bird int; odds jsonb := public.config_get('rarity') -> 'animals' -> 'purchase_odds';
  u double precision; acc double precision := 0; v_rar text; k text; fx jsonb; v_feed numeric; v_gold numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if d is null or d ->> 'house' <> p_house then raise exception 'animal não é dessa casa' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if not public.house_ready(v_user, p_house, v_time) then raise exception 'casa ainda não existe' using errcode = 'check_violation'; end if;
  if (d ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_base := public.house_slots(v_user, p_house);
  v_bird := public.house_bird_slots(v_user, p_house, v_time);
  if p_slot is null or p_slot < 1 or p_slot > v_base + v_bird then raise exception 'vaga não existe' using errcode = 'check_violation'; end if;
  if p_slot > v_base and not (d ->> 'is_bird')::boolean then raise exception 'vaga do Lago é só para aves' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.animals where user_id = v_user and house_id = p_house and slot = p_slot) then
    raise exception 'vaga ocupada' using errcode = 'check_violation';
  end if;
  perform public.ledger_post(v_user, -(d ->> 'buy_cost')::numeric, 'animal_buy', jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', p_animal));
  -- sorteio criptográfico da raridade, gravado antes de aparecer na tela
  u := public.rand01();
  for k in select x from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) x loop
    acc := acc + coalesce((odds ->> k)::double precision, 0);
    v_rar := k;
    exit when u < acc;
  end loop;
  insert into public.animals (user_id, house_id, slot, animal_id, rarity) values (v_user, p_house, p_slot, p_animal, v_rar);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'animal.bought', v_user, jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', p_animal, 'rarity', v_rar, 'roll', round(u::numeric, 6)));
  fx := public.team_fx(v_user);
  select gold into v_gold from public.wallets where user_id = v_user;
  v_feed := public.animal_start(v_user, p_house, p_slot, v_time, fx, v_gold);
  if v_feed > 0 then perform public.ledger_post(v_user, -v_feed, 'feed', jsonb_build_object('house', p_house, 'slot', p_slot)); end if;
  return public.farm_state(v_user);
end;
$$;

-- tirar o animal da vaga (não devolve ouro)
create or replace function public.remove_animal(p_house text, p_slot int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); a public.animals;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  delete from public.animals where user_id = v_user and house_id = p_house and slot = p_slot returning * into a;
  if not found then raise exception 'vaga vazia' using errcode = 'check_violation'; end if;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'animal.removed', v_user, jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', a.animal_id, 'rarity', a.rarity));
  return public.farm_state(v_user);
end;
$$;

-- ampliar a casa (4 → 8 → 12 vagas); a Mestria de Obras do Ferreiro dá desconto
create or replace function public.upgrade_house(p_house text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_tier int; v_next jsonb; v_level int; v_time double precision; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.config_get('animals') -> 'houses' -> p_house is null then raise exception 'casa não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if not public.house_ready(v_user, p_house, v_time) then raise exception 'casa ainda não existe' using errcode = 'check_violation'; end if;
  insert into public.animal_houses (user_id, house_id) values (v_user, p_house) on conflict do nothing;
  select tier into v_tier from public.animal_houses where user_id = v_user and house_id = p_house for update;
  v_next := public.config_get('animals') -> 'houses' -> p_house -> 'slots' -> (v_tier + 1);
  if v_next is null then raise exception 'casa já está no máximo' using errcode = 'check_violation'; end if;
  if v_level < (v_next ->> 'min_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_cost := round((v_next ->> 'cost')::numeric * (1 + (public.team_fx(v_user) ->> 'expansion_cost')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'house_upgrade', jsonb_build_object('house', p_house, 'slots', v_next -> 'slots'), 'house:' || p_house || ':' || (v_tier + 1));
  update public.animal_houses set tier = v_tier + 1 where user_id = v_user and house_id = p_house;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'house.upgraded', v_user, jsonb_build_object('house', p_house, 'tier', v_tier + 1, 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;

-- admin: terminar o ciclo dos animais (para testes), com justificativa e auditoria
create or replace function public.admin_finish_animals(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_time double precision; n int;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  select farm_time into v_time from public.farms where user_id = p_user;
  update public.animals set ready_at = v_time where user_id = p_user and state = 'growing' and ready_at > v_time;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'nenhum animal produzindo' using errcode = 'check_violation'; end if;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.finish_animals', p_user, jsonb_build_object('animals', n, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- ---------- permissões ----------
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.animal_def(text)', 'public.item_price(text)', 'public.house_lot(text)', 'public.house_ready(uuid, text, double precision)',
    'public.lake_ready(uuid, double precision)', 'public.house_slots(uuid, text)', 'public.house_bird_slots(uuid, text, double precision)',
    'public.animal_start(uuid, text, int, double precision, jsonb, numeric)', 'public.animal_collect(uuid, text, int, double precision, jsonb, boolean)',
    'public.animals_feed_hungry(uuid, double precision, jsonb, numeric)', 'public.feed_hungry_now(uuid)', 'public.team_fx(uuid)', 'public.char_energy(public.characters, jsonb)',
    'public.advance_farm(uuid, timestamptz)', 'public.tend_plots(uuid, text, boolean, boolean)', 'public.farm_state(uuid)', 'public.auto_sell(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array[
    'public.buy_animal(text, int, text)', 'public.remove_animal(text, int)', 'public.upgrade_house(text)', 'public.admin_finish_animals(uuid, text)',
    'public.sell_at_stall(text, int, text)', 'public.set_auto_sell(text, boolean)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
