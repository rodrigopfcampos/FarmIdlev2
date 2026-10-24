-- Fase 3: personagens. 6 classes com contratação, Slots de Campo e de Banco, energia e rodízio, lanches,
-- salário à meia-noite (Brasília até a fase 6), Desmotivado e parada depois de 3 dias devendo, nível e
-- árvore de habilidades com reset, ferramenta de cada classe com desgaste e conserto, funções de apoio
-- em campo (Comerciante, Gerente, Botânica), sementes raras e pets com carinho diário.
-- Números só da config (game_config: characters, tools_and_items, rarity, crops, levels, lots).

-- ---------- tabelas ----------
create table public.characters (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  class_id text not null,
  slot text not null default 'field' check (slot in ('field', 'bench')),
  energy double precision not null default 100 check (energy >= 0),
  parked boolean not null default false,          -- parado no slot descansando até a energia de volta
  level integer not null default 1 check (level between 1 and 30),
  work_hours double precision not null default 0, -- horas trabalhadas rumo ao próximo nível
  skills jsonb not null default '{}'::jsonb,      -- pontos por nó: {"cultivo.a": 5, "cultivo.m": 3}
  skill_choice text,                              -- cultivo escolhido na Mestria "libera antes"
  reset_week text,                                -- semana (ISO) do último reset grátis
  debt numeric(18, 2) not null default 0 check (debt >= 0),
  unpaid_days integer not null default 0 check (unpaid_days >= 0),
  snack_id text,
  snack_qty integer not null default 0 check (snack_qty between 0 and 5),
  cloth_id text,                                  -- vestimenta e amuleto chegam nas expedições (fase 5)
  amulet_id text,
  revive_day date,                                -- Mestria de Resistência do Agricultor (1×/dia)
  hired_at timestamptz not null default now(),
  primary key (user_id, class_id)
);

create table public.pets (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  pet_id text not null,
  affinity integer not null default 0 check (affinity >= 0),
  last_care date,
  active boolean not null default false,
  linked_class text,
  adopted_at timestamptz not null default now(),
  primary key (user_id, pet_id)
);
create unique index pets_one_active on public.pets (user_id) where active;

alter table public.tools add column durability double precision not null default 100 check (durability between 0 and 100);
alter table public.silo add column auto_sell boolean not null default false;
alter table public.plots add column rarity text;                          -- semente rara do plantio atual (null = Comum)
alter table public.plots add column seed_paid numeric(18, 2) not null default 0;
alter table public.trees add column rarity text;                          -- muda rara: vale as próximas N colheitas
alter table public.trees add column rare_left integer not null default 0;
alter table public.farms add column last_payday date;                     -- último dia cujo salário já foi cobrado
alter table public.farms add column boosted_sale_day date;                -- venda 1,5× do dia (Mestria da Barraca)
alter table public.farms add column pet_swapped_at timestamptz;           -- troca do pet ativo tem espera

alter table public.characters enable row level security;
alter table public.pets enable row level security;
create policy characters_read_own on public.characters for select to authenticated using (user_id = (select auth.uid()));
create policy pets_read_own on public.pets for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.characters, public.pets from anon, authenticated;

-- quem já tinha fazenda: Agricultor no campo, dia do salário = hoje
insert into public.characters (user_id, class_id) select user_id, 'agricultor' from public.farms on conflict do nothing;
update public.farms set last_payday = (now() at time zone 'America/Sao_Paulo')::date where last_payday is null;

-- ---------- ajudantes ----------
-- número aleatório criptográfico em [0, 1)
create or replace function public.rand01()
returns double precision
language sql volatile
set search_path = ''
as $$
  select (('x' || encode(extensions.gen_random_bytes(7), 'hex'))::bit(56)::bigint)::double precision / 72057594037927936.0
$$;

-- Renda de Referência do nível
create or replace function public.ref_income(p_level int)
returns numeric
language sql stable
set search_path = ''
as $$
  select (public.config_get('levels') -> 'levels' -> (greatest(1, least(50, p_level)) - 1) ->> 'reference_income_per_day')::numeric
$$;

create or replace function public.class_def(p_class text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('characters') -> 'classes') x where x ->> 'id' = p_class
$$;

-- índice do material (Madeira 0 … Cristal 4) e o dado do material
create or replace function public.material_idx(p_material text)
returns int
language sql stable
set search_path = ''
as $$
  select (ord - 1)::int from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') with ordinality m(x, ord)
  where x ->> 'id' = coalesce(p_material, 'wood')
$$;

create or replace function public.material_def(p_material text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') x where x ->> 'id' = coalesce(p_material, 'wood')
$$;

-- dia de hoje no fuso do salário (Brasília até a fase 6)
create or replace function public.game_day(p_at timestamptz default now())
returns date
language sql stable
set search_path = ''
as $$
  select (p_at at time zone coalesce(public.config_get('characters') ->> 'payday_timezone', 'America/Sao_Paulo'))::date
$$;

-- valor de um efeito na árvore de habilidades de um personagem (nós ativos só até a fase atual)
create or replace function public.skill_effect(p_class text, p_skills jsonb, p_effect text)
returns double precision
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') c),
  br as (select x, (select (c ->> 'active_phase')::int from cfg) ph, (select (c -> 'skills' ->> 'mastery_points')::int from cfg) mp
         from cfg, jsonb_array_elements(c -> 'skill_tree' -> p_class) x)
  select coalesce(sum(
      case when x -> 'a' ->> 'effect' = p_effect and coalesce((x -> 'a' ->> 'phase')::int, 0) <= ph
           then coalesce((p_skills ->> (x ->> 'id' || '.a'))::double precision, 0) * (x -> 'a' ->> 'per_point')::double precision else 0 end
    + case when x -> 'b' ->> 'effect' = p_effect and coalesce((x -> 'b' ->> 'phase')::int, 0) <= ph
           then coalesce((p_skills ->> (x ->> 'id' || '.b'))::double precision, 0) * (x -> 'b' ->> 'per_point')::double precision else 0 end
    + case when x -> 'mastery' ->> 'effect' = p_effect and coalesce((x -> 'mastery' ->> 'phase')::int, 0) <= ph
                and coalesce((p_skills ->> (x ->> 'id' || '.m'))::int, 0) >= mp
           then (x -> 'mastery' ->> 'value')::double precision else 0 end), 0)
  from br
$$;

-- pet ativo: id, nível (pela afinidade), fator do efeito (40% → 100%) e personagem vinculado
create or replace function public.pet_info(p_user uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') -> 'pets' c)
  select jsonb_build_object('id', p.pet_id, 'level', lv, 'linked', p.linked_class,
           'factor', (c ->> 'effect_at_level_1')::double precision
                     + ((c ->> 'effect_at_level_5')::double precision - (c ->> 'effect_at_level_1')::double precision) * (lv - 1) / 4.0)
  from public.pets p, cfg,
       lateral (select 1 + (select count(*) from jsonb_array_elements_text(c -> 'affinity_to_level') a where a::int <= p.affinity)::int lv) l
  where p.user_id = p_user and p.active
$$;

-- personagem em campo que conta para os efeitos: no Slot de Campo e sem 3 dias de salário atrasado
create or replace function public.char_active(c public.characters)
returns boolean
language sql stable
set search_path = ''
as $$
  select c.slot = 'field' and c.unpaid_days < coalesce((public.config_get('characters') -> 'salary' ->> 'stops_after_days')::int, 3)
$$;

-- efeitos da equipe em campo, calculados uma vez por passo do servidor
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
    'orchard_extra_fruit_chance', 'early_unlock_levels'];
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0;
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
  end loop;
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    if pet ->> 'id' = 'gato' then
      gato := (select (x ->> 'energy_recovery_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'papagaio' then
      papagaio := (select (x ->> 'sales_gold_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio') / 100 * (pet ->> 'factor')::double precision;
    end if;
  end if;
  return jsonb_build_object(
    'growth_crop', ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100,
    'growth_orchard', ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100,
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', (s ->> 'double_harvest_crop_pct')::double precision / 100,
    'golden', least((crops -> 'golden_harvest' ->> 'cap_permanent')::double precision, (s ->> 'golden_pct')::double precision / 100),
    'golden_mult', (crops -> 'golden_harvest' ->> 'multiplier')::double precision,
    'harvest_xp', ((s ->> 'harvest_xp_pct')::double precision + case when bot then (fe -> 'botanica' ->> 'harvest_xp_pct')::double precision else 0 end) / 100,
    'account_xp', (s ->> 'account_xp_pct')::double precision / 100,
    'recurring', (s ->> 'recurring_production_pct')::double precision / 100,
    'extra_fruit', (s ->> 'orchard_extra_fruit_chance')::double precision,
    'seed_discount', least(0.9, (-(s ->> 'seed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'seed_discount_pct_per_material')::double precision * (com + 1) else 0 end) / 100),
    'shop_discount', least(0.9, -(s ->> 'shop_discount_pct')::double precision / 100),
    'stall_ratio', least((fe -> 'comerciante' ->> 'stall_price_cap')::double precision,
                   base_stall + ((s ->> 'stall_price_pts')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'stall_price_pts_per_material')::double precision * (com + 1) else 0 end) / 100),
    'sales_gold', (s ->> 'sales_gold_pct')::double precision / 100 + papagaio,
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

-- trabalho por hora de um personagem (sem contar energia), já com ferramenta, função, habilidade, dívida e pet
create or replace function public.char_rate(c public.characters, p_material text, p_durability double precision, fx jsonb)
returns double precision
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') ch, public.config_get('tools_and_items') -> 'tool_durability_rules' dr)
  select (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision
       * (public.material_def(p_material) ->> 'work_capacity_multiplier')::double precision * (1 + (fx ->> 'tool_effect')::double precision)
       * case when p_durability < (dr ->> 'low_durability_threshold')::double precision then (dr ->> 'low_durability_capacity_penalty_multiplier')::double precision else 1 end
       * coalesce((ch -> 'role_efficiency' ->> (public.class_def(c.class_id) ->> 'role'))::double precision, (ch -> 'role_efficiency' ->> 'other')::double precision)
       * (1 + public.skill_effect(c.class_id, c.skills, 'work_capacity_pct') / 100 + (fx ->> 'team_capacity')::double precision)
       * case when c.debt > 0 then (ch -> 'salary' ->> 'unpaid_efficiency')::double precision else 1 end
       * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 + (ch -> 'pets' ->> 'per_level_work_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end
  from cfg
$$;

-- energia máxima, gasto por hora trabalhada e recuperação por hora de descanso
create or replace function public.char_energy(c public.characters, fx jsonb)
returns jsonb
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy'),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(0.2, (1 + public.skill_effect(c.class_id, c.skills, 'energy_use_pct') / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 - (ch -> 'pets' ->> 'per_level_energy_use_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * (1 + (fx ->> 'gato_rest')::double precision) * (1 + public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') / 100))
  from cfg
$$;

-- salário do dia de um personagem: 2% de R do nível da conta × (1 + 1% × nível do personagem)
create or replace function public.salary_of(p_user uuid, c public.characters)
returns numeric
language sql stable
set search_path = ''
as $$
  select case when c.class_id = 'agricultor' then 0 else
    round(public.ref_income((select level from public.farms where user_id = p_user))
      * (public.config_get('characters') -> 'salary' ->> 'share_of_R')::numeric
      * (1 + (public.config_get('characters') -> 'salary' ->> 'per_character_level')::numeric * c.level), 2) end
$$;

-- cobra os salários de cada meia-noite até p_until; sem ouro, o dia vira dívida
create or replace function public.process_payday(p_user uuid, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last date; v_today date := public.game_day(p_until); v_gold numeric; v_sal numeric; c public.characters;
begin
  select coalesce(last_payday, v_today) into v_last from public.farms where user_id = p_user for update;
  while v_last < v_today loop
    v_last := v_last + 1;
    for c in select * from public.characters where user_id = p_user and class_id <> 'agricultor' order by hired_at loop
      v_sal := public.salary_of(p_user, c);
      if v_sal <= 0 then continue; end if;
      select gold into v_gold from public.wallets where user_id = p_user;
      if c.debt = 0 and v_gold >= v_sal then
        perform public.ledger_post(p_user, -v_sal, 'salary', jsonb_build_object('class', c.class_id, 'day', v_last), 'salary:' || c.class_id || ':' || v_last);
      else
        update public.characters set debt = debt + v_sal, unpaid_days = unpaid_days + 1 where user_id = p_user and class_id = c.class_id;
      end if;
    end loop;
  end loop;
  update public.farms set last_payday = v_last where user_id = p_user;
end;
$$;

-- paga as dívidas de salário que couberem no ouro (botão da Casa, ou sozinho com o Gerente em campo)
create or replace function public.pay_debts(p_user uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare c public.characters; v_gold numeric; n int := 0;
begin
  for c in select * from public.characters where user_id = p_user and debt > 0 order by hired_at for update loop
    select gold into v_gold from public.wallets where user_id = p_user;
    exit when v_gold < c.debt;
    perform public.ledger_post(p_user, -c.debt, 'salary_debt', jsonb_build_object('class', c.class_id, 'days', c.unpaid_days));
    update public.characters set debt = 0, unpaid_days = 0 where user_id = p_user and class_id = c.class_id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- rodízio (4 ou mais personagens): quem chega a 10 sai do campo e entra quem tem 60 ou mais, de preferência da mesma função
create or replace function public.rotate_team(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e jsonb := public.config_get('characters') -> 'energy';
  slots int := (public.config_get('characters') ->> 'field_slots')::int;
  c record; b record; n_field int;
begin
  if (select count(*) from public.characters where user_id = p_user) < (e ->> 'rotation_from_characters')::int then return; end if;
  for c in select ch.class_id, public.class_def(ch.class_id) ->> 'role' as role from public.characters ch
           where ch.user_id = p_user and ch.slot = 'field' and ch.energy <= (e ->> 'leave_field_at')::double precision order by ch.energy loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.energy >= (e ->> 'enter_field_at')::double precision
      order by (public.class_def(ch.class_id) ->> 'role' = c.role) desc, ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'bench', parked = false where user_id = p_user and class_id = c.class_id;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
  end loop;
  -- vaga livre no campo: entra quem está descansado
  select count(*) into n_field from public.characters where user_id = p_user and slot = 'field';
  while n_field < slots loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.energy >= (e ->> 'enter_field_at')::double precision order by ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
    n_field := n_field + 1;
  end loop;
end;
$$;

-- passo de tempo dos personagens: quem trabalha gasta energia, ganha horas e desgasta a ferramenta (na fração
-- do tempo em que houve trabalho); quem está no banco ou parado descansa; lanche quando a energia cai
create or replace function public.tick_team(p_user uuid, p_hours double precision, p_frac double precision, fx jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  cfg jsonb := public.config_get('characters');
  dr jsonb := public.config_get('tools_and_items') -> 'tool_durability_rules';
  snacks jsonb := public.config_get('tools_and_items') -> 'snack_cards';
  c public.characters; en jsonb; v_e double precision; v_h double precision; v_lvl int; v_park boolean; v_qty int; v_rev date;
  v_today date := public.game_day(now()); s jsonb; worked double precision;
begin
  for c in select * from public.characters where user_id = p_user for update loop
    en := public.char_energy(c, fx);
    v_e := c.energy; v_h := c.work_hours; v_lvl := c.level; v_park := c.parked; v_qty := c.snack_qty; v_rev := c.revive_day;
    if c.slot = 'field' and not c.parked and public.char_active(c) and c.energy > 0 then
      worked := p_hours * p_frac;
      v_e := v_e - (en ->> 'use')::double precision * worked;
      v_h := v_h + worked;
      update public.tools set durability = greatest(0, durability - (dr ->> 'loss_per_work_hour')::double precision * worked)
        where user_id = p_user and class_id = c.class_id;
      if v_e <= 0 then
        v_e := 0;
        if public.skill_effect(c.class_id, c.skills, 'daily_revive_energy') > 0 and v_rev is distinct from v_today then
          v_e := public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'); v_rev := v_today;
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
        v_e := least((en ->> 'max')::double precision, v_e + (s ->> 'energy_restore')::double precision);
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
    update public.characters set energy = v_e, work_hours = v_h, level = v_lvl, parked = v_park, snack_qty = v_qty,
        snack_id = case when v_qty = 0 then null else snack_id end, revive_day = v_rev
      where user_id = p_user and class_id = c.class_id;
  end loop;
end;
$$;

-- trabalho por hora da equipe agora (quem está trabalhando) e o nominal (todos do campo, para o teto guardado)
create or replace function public.team_rate(p_user uuid, fx jsonb)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'working', coalesce(sum(r) filter (where ch.slot = 'field' and not ch.parked and ch.energy > 0 and public.char_active(ch)), 0),
    'nominal', coalesce(sum(r) filter (where ch.slot = 'field'), 0))
  from public.characters ch
  left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id,
  lateral (select public.char_rate(ch, t.material, coalesce(t.durability, 100), fx) r) x
  where ch.user_id = p_user
$$;

-- venda automática do Comerciante: itens marcados no Silo, no preço da Barraca
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
    v_price := (public.crop_def(r.item_id) ->> 'fair_price_per_unit')::numeric;
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

-- multiplicador da raridade (null = Comum)
create or replace function public.rarity_mult(p_rarity text)
returns double precision
language sql stable
set search_path = ''
as $$
  select coalesce((select (x ->> 'multiplier')::double precision from jsonb_array_elements(public.config_get('rarity') -> 'tiers') x where x ->> 'id' = p_rarity), 1)
$$;

-- arredonda uma quantidade fracionária sorteando a parte quebrada (2,3 vira 3 em 30% das vezes)
create or replace function public.round_rand(p_x double precision)
returns int
language sql volatile
set search_path = ''
as $$
  select floor(p_x + public.rand01())::int
$$;

-- Botânica: sorteio de Semente Rara na colheita
create or replace function public.roll_rare_seed(p_user uuid, p_crop text, fx jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare odds jsonb := public.config_get('characters') -> 'field_effects' -> 'botanica' -> 'rare_seed_odds'; u double precision; acc double precision := 0; k text;
begin
  if coalesce((fx ->> 'rare_seed')::double precision, 0) <= 0 or public.rand01() >= (fx ->> 'rare_seed')::double precision then return; end if;
  u := public.rand01();
  for k in select x from unnest(array['uncommon', 'rare', 'legendary', 'mythic']) x loop
    acc := acc + coalesce((odds ->> k)::double precision, 0);
    if u < acc or k = 'mythic' then
      insert into public.inventory (user_id, item_id, qty) values (p_user, 'seed:' || p_crop || ':' || k, 1)
        on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
      insert into public.audit_log (actor_id, action, target_user_id, data) values (null, 'seed.rare_drop', p_user, jsonb_build_object('crop', p_crop, 'rarity', k));
      return;
    end if;
  end loop;
end;
$$;

-- ---------- plantio e colheita com os efeitos da equipe ----------
-- planta um canteiro no instante p_t; devolve o ouro gasto na semente (0 com Semente Rara)
create or replace function public.plant_plot(p_user uuid, p_plot text, p_crop text, p_t double precision, fx jsonb, p_rarity text default null)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare c jsonb := public.crop_def(p_crop); v_seed numeric;
begin
  v_seed := case when p_rarity is null then round((c ->> 'seed_cost')::numeric * (1 - (fx ->> 'seed_discount')::numeric), 2) else 0 end;
  update public.plots
    set state = 'growing', planted_crop_id = p_crop, planted_kind = c ->> 'kind', planted_at = p_t, harvests_done = 0,
        ready_at = p_t + (c ->> 'grow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision),
        free_since = null, stalled_reason = null, rarity = p_rarity, seed_paid = v_seed
    where user_id = p_user and plot_id = p_plot;
  return v_seed;
end;
$$;

-- custo da semente agora (para saber se há ouro antes de plantar)
create or replace function public.seed_price(p_crop text, fx jsonb)
returns numeric
language sql stable
set search_path = ''
as $$
  select round((public.crop_def(p_crop) ->> 'seed_cost')::numeric * (1 - (fx ->> 'seed_discount')::numeric), 2)
$$;

drop function if exists public.harvest_plot(uuid, text, double precision);
drop function if exists public.harvest_tree(uuid, text, int, double precision);

-- colhe um canteiro no instante p_t; devolve o ouro da semente devolvido pela Botânica (0 se não saiu)
create or replace function public.harvest_plot(p_user uuid, p_plot text, p_t double precision, fx jsonb)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  pl public.plots; c jsonb; v_done int; v_total int; m double precision; rm double precision; v_refund numeric := 0;
begin
  select * into pl from public.plots where user_id = p_user and plot_id = p_plot for update;
  c := public.crop_def(pl.planted_crop_id);
  rm := public.rarity_mult(pl.rarity);
  m := rm * (1 + case when c ->> 'kind' = 'recurring' then (fx ->> 'recurring')::double precision else 0 end);
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  if c ->> 'kind' = 'crop' and public.rand01() < (fx ->> 'double_crop')::double precision then m := m * 2; end if;
  insert into public.silo (user_id, item_id, qty) values (p_user, pl.planted_crop_id, public.round_rand((c ->> 'units_per_harvest')::double precision * m))
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
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
$$;

create or replace function public.harvest_tree(p_user uuid, p_lot text, p_slot int, p_t double precision, fx jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare tr public.trees; c jsonb; m double precision; rm double precision; v_qty int;
begin
  select * into tr from public.trees where user_id = p_user and lot_id = p_lot and slot = p_slot for update;
  c := public.crop_def(tr.fruit_id);
  rm := case when tr.rare_left > 0 then public.rarity_mult(tr.rarity) else 1 end;
  m := rm;
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  v_qty := public.round_rand((c ->> 'units_per_harvest')::double precision * m);
  if public.rand01() < (fx ->> 'extra_fruit')::double precision then v_qty := v_qty + 1; end if;
  insert into public.silo (user_id, item_id, qty) values (p_user, tr.fruit_id, v_qty)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, tr.fruit_id, fx);
  update public.trees set ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_orchard')::double precision),
      rare_left = greatest(0, rare_left - 1), rarity = case when rare_left <= 1 then null else rarity end
    where user_id = p_user and lot_id = p_lot and slot = p_slot;
end;
$$;

-- ---------- avanço da fazenda (fase 3) ----------
-- Anda em passos (config characters.step_minutes). Em cada passo: salários das meias-noites que passaram,
-- dívida paga pelo Gerente, rodízio, efeitos da equipe, fila única de tarefas (plantar 0,5; colher 0,5) com o
-- trabalho de quem está em campo e com energia, depois energia/nível/desgaste/lanches e a venda automática.
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
  v_gold numeric; v_seed_spent numeric; v_refund numeric; v_plantings int; v_seed numeric;
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
        if v_gold - v_seed_spent < v_seed then
          update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
          continue;
        end if;
        v_seed_spent := v_seed_spent + public.plant_plot(p_user, e.key, (select crop_id from public.plots where user_id = p_user and plot_id = e.key), te, fx);
        v_plantings := v_plantings + 1;
      elsif e.kind = 'harvest' then
        v_refund := v_refund + public.harvest_plot(p_user, e.key, te, fx);
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

-- ---------- clique do jogador (grátis) com os efeitos da equipe ----------
create or replace function public.tend_plots(p_user uuid, p_target text, p_harvest boolean, p_plant boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_time double precision; fx jsonb := public.team_fx(p_user);
  v_gold numeric; v_seed_spent numeric := 0; v_refund numeric := 0; v_plantings int := 0; v_seed numeric;
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

-- ---------- estado para o jogo ----------
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
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p.pet_id, 'affinity', p.affinity, 'last_care', p.last_care,
        'active', p.active, 'linked_class', p.linked_class) order by p.adopted_at), '[]') from public.pets p where p.user_id = p_user),
    'pet', fx -> 'pet',
    'snack_prices', v_snacks,
    'fx', jsonb_build_object('stall_ratio', fx -> 'stall_ratio', 'seed_discount', fx -> 'seed_discount', 'sales_gold', fx -> 'sales_gold',
        'shop_discount', fx -> 'shop_discount', 'auto_sell', fx -> 'auto_sell', 'auto_pay', fx -> 'auto_pay', 'rare_seed', fx -> 'rare_seed',
        'seed_refund', fx -> 'seed_refund', 'gerente_cut', fx -> 'gerente_cut', 'early_unlock', fx -> 'early_unlock', 'daily_boost', fx -> 'daily_boost',
        'growth_crop', fx -> 'growth_crop', 'growth_orchard', fx -> 'growth_orchard', 'tree_initial', fx -> 'tree_initial', 'cleanup', fx -> 'cleanup',
        'tool_cost', fx -> 'tool_cost', 'harvest_xp', fx -> 'harvest_xp', 'golden', fx -> 'golden')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base;
end;
$$;

-- ---------- criação da fazenda (agora com o Agricultor e o dia do salário) ----------
create or replace function public.create_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_farm jsonb := public.config_get('farm');
  v_crops jsonb := public.config_get('crops');
  v_lot text := coalesce(v_farm ->> 'starting_lot', 'A1');
  v_rate double precision := (v_crops -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision;
  k int;
begin
  insert into public.farms (user_id, labor_bank, last_payday)
    values (p_user, coalesce(v_rate, 0) * coalesce((v_farm ->> 'initial_labor_bank_hours')::double precision, 0), public.game_day(now()))
    on conflict do nothing;
  insert into public.owned_lots (user_id, lot_id) values (p_user, v_lot) on conflict do nothing;
  for k in 1 .. coalesce((v_farm ->> 'plots_per_crop_lot')::int, 8) loop
    insert into public.plots (user_id, plot_id) values (p_user, v_lot || '-' || k) on conflict do nothing;
  end loop;
  insert into public.tools (user_id, class_id) values (p_user, 'agricultor') on conflict do nothing;
  insert into public.characters (user_id, class_id) values (p_user, 'agricultor') on conflict do nothing;
end;
$$;

-- cultivo liberado no nível (ou pela Mestria da Botânica, 3 níveis antes)
create or replace function public.crop_unlocked(p_user uuid, c jsonb, fx jsonb)
returns boolean
language sql stable
set search_path = ''
as $$
  select (c ->> 'unlock_level')::int <= f.level
      or coalesce(fx -> 'early_unlock' ->> 'crop' = c ->> 'id' and (c ->> 'unlock_level')::int <= f.level + (fx -> 'early_unlock' ->> 'levels')::int, false)
  from public.farms f where f.user_id = p_user
$$;

create or replace function public.set_crop(p_target text, p_crop text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_time double precision;
  c jsonb;
  n int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or length(p_target) > 8 or p_target !~ '^[A-Z][0-9]{0,2}(-[0-9]{1,2})?$' then
    raise exception 'canteiro não encontrado' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  if p_crop is not null then
    c := public.crop_def(p_crop);
    if c is null or (c ->> 'kind') = 'orchard' then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
    if not public.crop_unlocked(v_user, c, public.team_fx(v_user)) then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  end if;
  update public.plots
    set crop_id = p_crop, stalled_reason = null,
        free_since = case when state = 'empty' then v_time else free_since end
    where user_id = v_user and (plot_id = p_target or plot_id like p_target || '-%')
      and split_part(plot_id, '-', 1) in (select lot_id from public.owned_lots where user_id = v_user);
  get diagnostics n = row_count;
  if n = 0 then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  if p_crop is not null then perform public.tend_plots(v_user, p_target, false, true); end if;
  return public.farm_state(v_user);
end;
$$;

-- comprar lote: igual à fase 2; a limpeza volta ao tempo da tabela com o Ferreiro contratado (e o ramo Obras reduz)
create or replace function public.buy_lot(p_lot text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_lots jsonb := public.config_get('lots');
  v_map jsonb := public.config_get('map_rules');
  v_lot jsonb := public.lot_def(p_lot);
  v_n int; v_row jsonb; v_need_level int; v_level int; v_cost numeric; v_deed boolean;
  v_time double precision; v_minutes double precision; v_ready double precision;
  v_neighbor boolean; k int; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if v_lot is null then raise exception 'lote não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.owned_lots where user_id = v_user and lot_id = p_lot) then
    raise exception 'esse lote já é seu' using errcode = 'check_violation';
  end if;
  select count(*) into v_n from public.owned_lots where user_id = v_user;
  v_row := v_lots -> 'purchases' -> (v_n - 1);
  if v_row is null then raise exception 'todos os lotes já foram comprados' using errcode = 'check_violation'; end if;
  v_neighbor := (v_map -> 'exempt_types') ? (v_lot ->> 'type')
    or exists (select 1 from jsonb_array_elements_text(v_lot -> 'neighbors') nb
               join public.owned_lots ol on ol.user_id = v_user and ol.lot_id = nb);
  if not v_neighbor then raise exception 'lote não é vizinho' using errcode = 'check_violation'; end if;
  select level, farm_time into v_level, v_time from public.farms where user_id = v_user;
  v_need_level := greatest((v_row ->> 'min_level')::int, coalesce((v_lots -> 'rules' -> 'min_level' -> 'type_floor' ->> (v_lot ->> 'type'))::int, 0));
  if v_level < v_need_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_deed := (v_row ->> 'requires_deed')::boolean;
  if v_deed then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'deed' and qty >= 1;
    if not found then raise exception 'precisa de Escritura' using errcode = 'check_violation'; end if;
  end if;
  v_cost := (v_row ->> 'cost')::numeric;
  perform public.ledger_post(v_user, -v_cost, 'lot_purchase', jsonb_build_object('lot', p_lot, 'n', v_n, 'deed', v_deed), 'lot:' || p_lot);
  fx := public.team_fx(v_user);
  v_minutes := ((v_lots -> 'rules' -> 'cleanup' ->> 'base_minutes')::double precision
               + (v_lots -> 'rules' -> 'cleanup' ->> 'per_purchase_minutes')::double precision * v_n)
               * case when exists (select 1 from public.characters where user_id = v_user and class_id = 'ferreiro') then 1
                      else (v_lots -> 'rules' -> 'cleanup' ->> 'other_class_multiplier')::double precision end
               * (1 + (fx ->> 'cleanup')::double precision);
  v_ready := v_time + v_minutes * 60;
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (v_user, p_lot, v_ready, v_n);
  for k in 1 .. jsonb_array_length(coalesce(v_lot -> 'plots', '[]')) loop
    insert into public.plots (user_id, plot_id, free_since) values (v_user, v_lot -> 'plots' ->> (k - 1), v_ready);
  end loop;
  for k in 1 .. coalesce((v_lot ->> 'tree_slots')::int, 0) loop
    insert into public.trees (user_id, lot_id, slot) values (v_user, p_lot, k);
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'lot.bought', v_user, jsonb_build_object('lot', p_lot, 'n', v_n, 'cost', v_cost, 'deed', v_deed, 'cleanup_minutes', round(v_minutes::numeric, 1)));
  return public.farm_state(v_user);
end;
$$;

-- plantar muda no pomar; com p_rarity usa uma Semente Rara da fruta (sem pagar a muda; vale as próximas 6 colheitas)
drop function if exists public.plant_tree(text, int, text);
create or replace function public.plant_tree(p_lot text, p_slot int, p_fruit text, p_rarity text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  c jsonb := public.crop_def(p_fruit);
  v_time double precision; v_ready double precision; v_cost numeric; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if c is null or (c ->> 'kind') <> 'orchard' then raise exception 'fruta inválida' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  fx := public.team_fx(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  if p_rarity is null and not public.crop_unlocked(v_user, c, fx) then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  select ready_at into v_ready from public.owned_lots where user_id = v_user and lot_id = p_lot;
  if v_ready is null or not exists (select 1 from public.trees where user_id = v_user and lot_id = p_lot and slot = p_slot) then
    raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation';
  end if;
  if v_ready > v_time then raise exception 'lote ainda em limpeza' using errcode = 'check_violation'; end if;
  if p_rarity is not null then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'seed:' || p_fruit || ':' || p_rarity and qty >= 1;
    if not found then raise exception 'semente rara não encontrada' using errcode = 'check_violation'; end if;
  else
    v_cost := (c ->> 'sapling_cost')::numeric;
    perform public.ledger_post(v_user, -v_cost, 'sapling', jsonb_build_object('lot', p_lot, 'slot', p_slot, 'fruit', p_fruit));
  end if;
  update public.trees set fruit_id = p_fruit, planted_at = v_time,
      ready_at = v_time + (c ->> 'grow_minutes')::double precision * 60 * (1 + (fx ->> 'tree_initial')::double precision) / (1 + (fx ->> 'growth_orchard')::double precision),
      rarity = p_rarity, rare_left = case when p_rarity is null then 0 else coalesce((public.config_get('rarity') -> 'seeds' ->> 'tree_harvests')::int, 6) end
    where user_id = v_user and lot_id = p_lot and slot = p_slot;
  return public.farm_state(v_user);
end;
$$;

create or replace function public.chop_tree(p_lot text, p_slot int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  update public.trees set fruit_id = null, planted_at = null, ready_at = null, rarity = null, rare_left = 0
    where user_id = v_user and lot_id = p_lot and slot = p_slot;
  if not found then raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;

-- plantar uma Semente Rara num canteiro vazio (vale 1 plantio; o canteiro segue com o mesmo cultivo depois)
create or replace function public.plant_rare_seed(p_plot text, p_crop text, p_rarity text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_time double precision; pl public.plots; v_ready double precision; c jsonb := public.crop_def(p_crop);
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if c is null or c ->> 'kind' = 'orchard' then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  select * into pl from public.plots where user_id = v_user and plot_id = p_plot for update;
  if not found then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  select ready_at into v_ready from public.owned_lots where user_id = v_user and lot_id = split_part(p_plot, '-', 1);
  if v_ready > v_time then raise exception 'lote ainda em limpeza' using errcode = 'check_violation'; end if;
  if pl.state = 'growing' and pl.ready_at <= v_time then perform public.tend_plots(v_user, p_plot, true, false); end if;
  if (select state from public.plots where user_id = v_user and plot_id = p_plot) <> 'empty' then
    raise exception 'canteiro ocupado' using errcode = 'check_violation';
  end if;
  update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'seed:' || p_crop || ':' || p_rarity and qty >= 1;
  if not found then raise exception 'semente rara não encontrada' using errcode = 'check_violation'; end if;
  update public.plots set crop_id = p_crop where user_id = v_user and plot_id = p_plot;
  perform public.plant_plot(v_user, p_plot, p_crop, v_time, public.team_fx(v_user), p_rarity);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'seed.rare_planted', v_user, jsonb_build_object('plot', p_plot, 'crop', p_crop, 'rarity', p_rarity));
  return public.farm_state(v_user);
end;
$$;

-- vender na Barraca: preço com Comerciante e habilidades; Papagaio e Negócios aumentam o ouro; 1 venda 1,5× por dia
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
  v_price := (public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric;
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
  if public.crop_def(p_item) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  insert into public.silo (user_id, item_id, qty, auto_sell) values (v_user, p_item, 0, coalesce(p_on, false))
    on conflict (user_id, item_id) do update set auto_sell = coalesce(p_on, false);
  return public.farm_state(v_user);
end;
$$;

-- ---------- personagens ----------
create or replace function public.hire(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); d jsonb := public.class_def(p_class); v_level int; v_cost numeric; v_field int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if d is null then raise exception 'personagem não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem já contratado' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  if v_level < (d ->> 'unlock_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_cost := round((public.config_get('characters') -> 'hire_cost' ->> 'multiplier')::numeric * public.ref_income((d ->> 'unlock_level')::int), 2);
  if v_cost > 0 then perform public.ledger_post(v_user, -v_cost, 'hire', jsonb_build_object('class', p_class), 'hire:' || p_class); end if;
  select count(*) into v_field from public.characters where user_id = v_user and slot = 'field';
  insert into public.characters (user_id, class_id, slot) values (v_user, p_class,
    case when v_field < (public.config_get('characters') ->> 'field_slots')::int then 'field' else 'bench' end);
  insert into public.tools (user_id, class_id) values (v_user, p_class) on conflict do nothing;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'character.hired', v_user, jsonb_build_object('class', p_class, 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;

-- mover entre Slot de Campo e Slot de Banco
create or replace function public.set_slot(p_class text, p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_field int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_slot not in ('field', 'bench') then raise exception 'slot inválido' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem não contratado' using errcode = 'check_violation';
  end if;
  if p_slot = 'field' then
    select count(*) into v_field from public.characters where user_id = v_user and slot = 'field' and class_id <> p_class;
    if v_field >= (public.config_get('characters') ->> 'field_slots')::int then raise exception 'campo cheio' using errcode = 'check_violation'; end if;
  end if;
  update public.characters set slot = p_slot where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;

create or replace function public.pay_salaries()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and debt > 0) then
    raise exception 'nenhum salário atrasado' using errcode = 'check_violation';
  end if;
  if public.pay_debts(v_user) = 0 then raise exception 'ouro insuficiente' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;

-- ---------- lanches ----------
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

-- coloca lanches no espaço do personagem (até 5, de um tipo); null tira e devolve ao inventário
create or replace function public.equip_snack(p_class text, p_snack text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); c public.characters; v_have int; v_max int := 5; v_put int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found then raise exception 'personagem não contratado' using errcode = 'check_violation'; end if;
  -- devolve o que estava no espaço
  if c.snack_id is not null and c.snack_qty > 0 and (p_snack is null or p_snack <> c.snack_id) then
    insert into public.inventory (user_id, item_id, qty) values (v_user, c.snack_id, c.snack_qty)
      on conflict (user_id, item_id) do update set qty = public.inventory.qty + excluded.qty;
    update public.characters set snack_id = null, snack_qty = 0 where user_id = v_user and class_id = p_class;
    c.snack_qty := 0;
  end if;
  if p_snack is not null then
    v_max := coalesce((select (x ->> 'max_stack_in_slot')::int from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x where x ->> 'id' = p_snack), 0);
    if v_max = 0 then raise exception 'lanche não existe' using errcode = 'check_violation'; end if;
    select qty into v_have from public.inventory where user_id = v_user and item_id = p_snack for update;
    v_put := least(coalesce(v_have, 0), v_max - case when c.snack_id = p_snack then c.snack_qty else 0 end);
    if v_put <= 0 then raise exception 'sem lanche no inventário' using errcode = 'check_violation'; end if;
    update public.inventory set qty = qty - v_put where user_id = v_user and item_id = p_snack;
    update public.characters set snack_id = p_snack, snack_qty = snack_qty + v_put where user_id = v_user and class_id = p_class;
  end if;
  return public.farm_state(v_user);
end;
$$;

-- ---------- habilidades ----------
create or replace function public.skill_add(p_class text, p_node text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); cfg jsonb := public.config_get('characters'); c public.characters;
  v_branch text := split_part(p_node, '.', 1); v_part text := split_part(p_node, '.', 2);
  v_spent int; v_cur int; v_max int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if v_part not in ('a', 'b', 'm') or not exists (select 1 from jsonb_array_elements(cfg -> 'skill_tree' -> p_class) x where x ->> 'id' = v_branch) then
    raise exception 'habilidade não existe' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found then raise exception 'personagem não contratado' using errcode = 'check_violation'; end if;
  select coalesce(sum(value::int), 0) into v_spent from jsonb_each_text(c.skills);
  if v_spent >= (c.level - 1) * (cfg -> 'character_level' ->> 'skill_points_per_level')::int then
    raise exception 'sem pontos de habilidade' using errcode = 'check_violation';
  end if;
  v_cur := coalesce((c.skills ->> p_node)::int, 0);
  v_max := case when v_part = 'm' then (cfg -> 'skills' ->> 'mastery_points')::int else (cfg -> 'skills' ->> 'node_max')::int end;
  if v_cur >= v_max then raise exception 'habilidade no máximo' using errcode = 'check_violation'; end if;
  if v_part = 'm' and (coalesce((c.skills ->> (v_branch || '.a'))::int, 0) < (cfg -> 'skills' ->> 'node_max')::int
                    or coalesce((c.skills ->> (v_branch || '.b'))::int, 0) < (cfg -> 'skills' ->> 'node_max')::int) then
    raise exception 'complete os dois nós antes da Mestria' using errcode = 'check_violation';
  end if;
  update public.characters set skills = skills || jsonb_build_object(p_node, v_cur + 1) where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;

-- reset da árvore: 1 grátis por semana; outro custa 50% da Renda de Referência
create or replace function public.skill_reset(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); c public.characters; v_week text := to_char(public.game_day(now()), 'IYYY-IW'); v_level int; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found then raise exception 'personagem não contratado' using errcode = 'check_violation'; end if;
  if c.skills = '{}'::jsonb then raise exception 'nada para resetar' using errcode = 'check_violation'; end if;
  if c.reset_week is distinct from v_week then
    update public.characters set reset_week = v_week where user_id = v_user and class_id = p_class;
  else
    select level into v_level from public.farms where user_id = v_user;
    v_cost := round(public.ref_income(v_level) * (public.config_get('characters') -> 'skills' ->> 'extra_reset_cost_R_ratio')::numeric, 2);
    perform public.ledger_post(v_user, -v_cost, 'skill_reset', jsonb_build_object('class', p_class));
  end if;
  update public.characters set skills = '{}'::jsonb, skill_choice = null where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;

-- Mestria da Pesquisa (Botânica): escolhe o cultivo liberado 3 níveis antes
create or replace function public.skill_choose(p_class text, p_crop text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); c public.characters;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found or public.skill_effect(p_class, c.skills, 'early_unlock_levels') <= 0 then
    raise exception 'precisa da Mestria' using errcode = 'check_violation';
  end if;
  if public.crop_def(p_crop) is null then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
  update public.characters set skill_choice = p_crop where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;

-- ---------- ferramentas: melhorar e consertar (qualquer personagem contratado) ----------
create or replace function public.upgrade_tool(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_mats jsonb := public.config_get('tools_and_items') -> 'tool_materials';
  v_cur text; v_idx int; v_next jsonb; v_level int; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem não contratado' using errcode = 'check_violation';
  end if;
  select material into v_cur from public.tools where user_id = v_user and class_id = p_class for update;
  if v_cur is null then raise exception 'ferramenta não encontrada' using errcode = 'check_violation'; end if;
  v_idx := public.material_idx(v_cur);
  v_next := v_mats -> (v_idx + 1);
  if v_next is null then raise exception 'ferramenta já está no máximo' using errcode = 'check_violation'; end if;
  select level into v_level from public.farms where user_id = v_user;
  if (v_next ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_cost := round((v_next ->> 'upgrade_cost_gold')::numeric * (1 + (public.team_fx(v_user) ->> 'tool_cost')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'tool_upgrade',
    jsonb_build_object('class', p_class, 'from', v_cur, 'to', v_next ->> 'id'), 'tool:' || p_class || ':' || (v_next ->> 'id'));
  update public.tools set material = v_next ->> 'id', durability = 100 where user_id = v_user and class_id = p_class;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'tool.upgraded', v_user, jsonb_build_object('class', p_class, 'to', v_next ->> 'id', 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;

create or replace function public.repair_tool(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_mat text; v_dur double precision; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select material, durability into v_mat, v_dur from public.tools where user_id = v_user and class_id = p_class for update;
  if v_mat is null then raise exception 'ferramenta não encontrada' using errcode = 'check_violation'; end if;
  if v_dur >= 100 then raise exception 'ferramenta já está inteira' using errcode = 'check_violation'; end if;
  v_cost := round((public.material_def(v_mat) ->> 'repair_cost_gold')::numeric * (1 + (public.team_fx(v_user) ->> 'tool_cost')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'tool_repair', jsonb_build_object('class', p_class, 'material', v_mat, 'durability', round(v_dur::numeric, 1)));
  update public.tools set durability = 100 where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;

-- ---------- pets ----------
create or replace function public.adopt_pet(p_pet text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); cfg jsonb := public.config_get('characters') -> 'pets'; v_level int; v_n int; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from jsonb_array_elements(cfg -> 'list') x where x ->> 'id' = p_pet) then raise exception 'pet não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select level into v_level from public.farms where user_id = v_user;
  if v_level < (cfg ->> 'unlock_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.pets where user_id = v_user and pet_id = p_pet) then raise exception 'pet já adotado' using errcode = 'check_violation'; end if;
  select count(*) into v_n from public.pets where user_id = v_user;
  if v_n > 0 then
    v_cost := round(public.ref_income(v_level) * (cfg ->> 'extra_adoption_cost_R')::numeric, 2);
    perform public.ledger_post(v_user, -v_cost, 'pet_adoption', jsonb_build_object('pet', p_pet), 'pet:' || p_pet);
  end if;
  insert into public.pets (user_id, pet_id, active, linked_class) values (v_user, p_pet, v_n = 0, case when v_n = 0 then 'agricultor' end);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'pet.adopted', v_user, jsonb_build_object('pet', p_pet, 'cost', coalesce(v_cost, 0)));
  return public.farm_state(v_user);
end;
$$;

-- troca o pet ativo (espera de 7 dias entre trocas); o vínculo com o personagem passa para o novo
create or replace function public.set_active_pet(p_pet text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_since timestamptz; v_link text;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.pets where user_id = v_user and pet_id = p_pet) then raise exception 'pet não adotado' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.pets where user_id = v_user and pet_id = p_pet and active) then raise exception 'esse pet já está ativo' using errcode = 'check_violation'; end if;
  select pet_swapped_at into v_since from public.farms where user_id = v_user for update;
  if v_since is not null and v_since > now() - make_interval(days => (public.config_get('characters') -> 'pets' ->> 'swap_wait_days')::int) then
    raise exception 'troca do pet em espera' using errcode = 'check_violation';
  end if;
  select linked_class into v_link from public.pets where user_id = v_user and active;
  update public.pets set active = false, linked_class = null where user_id = v_user and active;
  update public.pets set active = true, linked_class = coalesce(v_link, 'agricultor') where user_id = v_user and pet_id = p_pet;
  update public.farms set pet_swapped_at = now() where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;

create or replace function public.link_pet(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem não contratado' using errcode = 'check_violation';
  end if;
  update public.pets set linked_class = p_class where user_id = v_user and active;
  if not found then raise exception 'nenhum pet ativo' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;

-- carinho diário: +1 de afinidade por pet por dia; o pet ativo dá +5 de energia ao personagem vinculado
create or replace function public.care_pet(p_pet text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_day date := public.game_day(now()); p public.pets; c public.characters;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into p from public.pets where user_id = v_user and pet_id = p_pet for update;
  if not found then raise exception 'pet não adotado' using errcode = 'check_violation'; end if;
  if p.last_care = v_day then raise exception 'carinho de hoje já foi dado' using errcode = 'check_violation'; end if;
  update public.pets set affinity = affinity + 1, last_care = v_day where user_id = v_user and pet_id = p_pet;
  if p.active and p.linked_class is not null then
    select * into c from public.characters where user_id = v_user and class_id = p.linked_class for update;
    if found then
      update public.characters set energy = least((public.char_energy(c, public.team_fx(v_user)) ->> 'max')::double precision,
          energy + (public.config_get('characters') -> 'pets' ->> 'care_energy')::double precision),
          parked = case when energy + (public.config_get('characters') -> 'pets' ->> 'care_energy')::double precision
                          >= (public.config_get('characters') -> 'energy' ->> 'parked_until')::double precision then false else parked end
        where user_id = v_user and class_id = p.linked_class;
    end if;
  end if;
  return public.farm_state(v_user);
end;
$$;

-- ---------- admin: cobrar o salário agora (para testar Desmotivado), com justificativa ----------
create or replace function public.admin_force_payday(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  update public.farms set last_payday = last_payday - 1 where user_id = p_user;
  if not found then raise exception 'fazenda não encontrada' using errcode = 'check_violation'; end if;
  perform public.process_payday(p_user, now());
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.force_payday', p_user, jsonb_build_object('reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- ---------- permissões ----------
do $$
declare fn text;
begin
  -- funções internas: ninguém de fora chama
  foreach fn in array array[
    'public.rand01()', 'public.ref_income(int)', 'public.class_def(text)', 'public.material_idx(text)', 'public.material_def(text)',
    'public.game_day(timestamptz)', 'public.skill_effect(text, jsonb, text)', 'public.pet_info(uuid)', 'public.char_active(public.characters)',
    'public.team_fx(uuid)', 'public.char_rate(public.characters, text, double precision, jsonb)', 'public.char_energy(public.characters, jsonb)',
    'public.salary_of(uuid, public.characters)', 'public.process_payday(uuid, timestamptz)', 'public.pay_debts(uuid)', 'public.rotate_team(uuid)',
    'public.tick_team(uuid, double precision, double precision, jsonb)', 'public.team_rate(uuid, jsonb)', 'public.auto_sell(uuid, jsonb)',
    'public.rarity_mult(text)', 'public.round_rand(double precision)', 'public.roll_rare_seed(uuid, text, jsonb)',
    'public.plant_plot(uuid, text, text, double precision, jsonb, text)', 'public.seed_price(text, jsonb)',
    'public.harvest_plot(uuid, text, double precision, jsonb)', 'public.harvest_tree(uuid, text, int, double precision, jsonb)',
    'public.advance_farm(uuid, timestamptz)', 'public.tend_plots(uuid, text, boolean, boolean)', 'public.farm_state(uuid)',
    'public.create_farm(uuid)', 'public.crop_unlocked(uuid, jsonb, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  -- ações do jogo: só logado
  foreach fn in array array[
    'public.set_crop(text, text)', 'public.buy_lot(text)', 'public.plant_tree(text, int, text, text)', 'public.chop_tree(text, int)',
    'public.plant_rare_seed(text, text, text)', 'public.sell_at_stall(text, int, text)', 'public.set_auto_sell(text, boolean)',
    'public.hire(text)', 'public.set_slot(text, text)', 'public.pay_salaries()', 'public.buy_snack(text, int)', 'public.equip_snack(text, text)',
    'public.skill_add(text, text)', 'public.skill_reset(text)', 'public.skill_choose(text, text)', 'public.upgrade_tool(text)',
    'public.repair_tool(text)', 'public.adopt_pet(text)', 'public.set_active_pet(text)', 'public.link_pet(text)', 'public.care_pet(text)',
    'public.admin_force_payday(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
