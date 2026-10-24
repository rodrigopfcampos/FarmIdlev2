-- Fase 5: expedições. Garagem com os 4 veículos (Carroça inicial), 5 rotas, raridade e reforma na Forja com Kits,
-- minigame de setas conferido no servidor, sorteio na volta (crítico, sucesso, falha parcial), seguro, garantia contra
-- azar, repetição automática com os mesmos produtos, desgaste e conserto, itens (vestimenta e amuleto), Escrituras,
-- demanda do dia igual para todos e relatório narrado. Decisões do dono (24/10/2026): o veículo volta e ESPERA o
-- clique em Receber; a repetição sai sozinha e também fica guardada; comboio com 1 minigame só.
-- Também: efeitos de expedição das habilidades (active_phase 5), Cachorro, roupas e amuletos nos personagens.

create table public.vehicles (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  vehicle_id text not null,
  rarity text not null default 'common',
  durability double precision not null default 100 check (durability between 0 and 100),
  active boolean not null default false,          -- o veículo que aparece na vaga da Garagem
  refurb_rarity text,                             -- reforma em andamento na Forja
  refurb_until double precision,                  -- tempo da fazenda
  bought_at timestamptz not null default now(),
  primary key (user_id, vehicle_id)
);

create table public.expeditions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.farms (user_id) on delete restrict,
  convoy_id uuid not null,
  vehicle_id text not null,
  route_id text not null,
  cargo jsonb not null,                           -- {item: qtd} que saiu do Silo
  cargo_value numeric(18, 2) not null,            -- a preço da rota, com a demanda do dia
  demand jsonb not null default '[]',             -- produtos da carga que estavam na demanda
  insurance numeric(18, 2) not null default 0,    -- pago na saída
  led boolean not null default false,             -- o Gerente conduz
  minigame text not null,                         -- perfect, done, incomplete, failed
  chance double precision not null,               -- chance de sucesso fixada na saída
  started_at double precision not null,           -- tempo da fazenda
  returns_at double precision not null,
  seq integer not null default 0,                 -- 0 = viagem do jogador; 1 e 2 = repetições
  repeat_left integer not null default 0,
  status text not null default 'travel' check (status in ('travel', 'back', 'collected')),
  outcome text check (outcome in ('crit', 'success', 'fail')),
  loss_frac double precision,
  gold numeric(18, 2) not null default 0,
  refund numeric(18, 2) not null default 0,
  cargo_back jsonb not null default '{}',
  drops jsonb not null default '[]',
  report text,
  created_at timestamptz not null default now(),
  collected_at timestamptz
);
create index expeditions_user_status on public.expeditions (user_id, status, returns_at);

create table public.minigames (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.farms (user_id) on delete restrict,
  route_id text not null,
  vehicles integer not null,
  manager boolean not null,
  calm boolean not null,
  arrows text[] not null,
  limit_ms integer not null,
  started_at timestamptz not null default now(),
  used boolean not null default false
);

create table public.daily_demand (
  day date not null,
  route_id text not null,
  products text[] not null,
  primary key (day, route_id)
);

alter table public.farms add column exp_fail_streak integer not null default 0;
alter table public.characters add column leading_id uuid;  -- comboio que o Gerente conduz (ocupa o slot, não trabalha)

alter table public.vehicles enable row level security;
alter table public.expeditions enable row level security;
alter table public.minigames enable row level security;
alter table public.daily_demand enable row level security;
create policy vehicles_read_own on public.vehicles for select to authenticated using (user_id = (select auth.uid()));
-- o resultado só aparece depois do clique em Receber (antes disso o jogador lê pela farm_state, sem o sorteio)
create policy expeditions_read_own on public.expeditions for select to authenticated using (user_id = (select auth.uid()) and status = 'collected');
create policy daily_demand_read on public.daily_demand for select to authenticated using (true);
revoke insert, update, delete, truncate on public.vehicles, public.expeditions, public.minigames, public.daily_demand from anon, authenticated;
revoke select on public.minigames from anon, authenticated;

-- a Carroça para quem já tem fazenda
insert into public.vehicles (user_id, vehicle_id, active) select user_id, 'carroca', true from public.farms on conflict do nothing;

-- ---------- ajudantes ----------
create or replace function public.exp_route(p_route text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('expeditions') -> 'routes') x where x ->> 'id' = p_route
$$;

create or replace function public.exp_route_idx(p_route text)
returns int
language sql stable
set search_path = ''
as $$
  select (o - 1)::int from jsonb_array_elements(public.config_get('expeditions') -> 'routes') with ordinality r(x, o) where x ->> 'id' = p_route
$$;

create or replace function public.vehicle_def(p_vehicle text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x where x ->> 'id' = p_vehicle
$$;

-- preço do veículo (a Carroça usa o preço de referência)
create or replace function public.vehicle_price(p_vehicle text)
returns numeric
language sql stable
set search_path = ''
as $$
  select case when (d ->> 'cost')::numeric > 0 then (d ->> 'cost')::numeric else coalesce((d ->> 'reference_cost')::numeric, 0) end
  from (select public.vehicle_def(p_vehicle) d) x
$$;

-- vestimenta ou amuleto: "cloth_hat:rare" → definição da carta
create or replace function public.equip_def(p_item text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements((public.config_get('tools_and_items') -> 'clothing_cards') || (public.config_get('tools_and_items') -> 'amulet_cards')) x
  where x ->> 'id' = split_part(p_item, ':', 1)
$$;

-- efeito de um item equipado no personagem (× raridade do item)
create or replace function public.item_effect(c public.characters, p_key text)
returns double precision
language sql stable
set search_path = ''
as $$
  select coalesce(sum((public.equip_def(i) -> 'base_effect' ->> p_key)::double precision
                      * coalesce((public.config_get('tools_and_items') -> 'equipment_rarities' -> split_part(i, ':', 2) ->> 'multiplier')::double precision, 1)), 0)
  from unnest(array[c.cloth_id, c.amulet_id]) i
  where i is not null
$$;

-- sorteio ponderado entre raridades {"common": 0.5, ...}
create or replace function public.pick_rarity(p_odds jsonb)
returns text
language plpgsql volatile
set search_path = ''
as $$
declare u double precision := public.rand01(); acc double precision := 0; k text; last_k text;
begin
  for k in select x from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) x loop
    if p_odds ? k then
      acc := acc + (p_odds ->> k)::double precision; last_k := k;
      if u < acc then return k; end if;
    end if;
  end loop;
  return last_k;
end;
$$;

-- demanda do dia: igual para todos, sorteada uma vez por dia (Brasília) entre todos os produtos do jogo
create or replace function public.demand_ensure(p_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r jsonb; n int := coalesce((public.config_get('expeditions') -> 'daily_demand' ->> 'products')::int, 3);
begin
  if exists (select 1 from public.daily_demand where day = p_day) then return; end if;
  for r in select x from jsonb_array_elements(public.config_get('expeditions') -> 'routes') x loop
    insert into public.daily_demand (day, route_id, products)
    select p_day, r ->> 'id', array(
      select id from (
        select x ->> 'id' id from jsonb_array_elements(public.config_get('crops') -> 'crops') x
        union select x -> 'product' ->> 'id' from jsonb_array_elements(public.config_get('animals') -> 'animals') x) p
      order by public.rand01() limit n)
    on conflict do nothing;
  end loop;
end;
$$;

create or replace function public.demand_of(p_day date, p_route text)
returns text[]
language sql stable
set search_path = ''
as $$
  select coalesce((select products from public.daily_demand where day = p_day and route_id = p_route), '{}')
$$;

-- o Gerente que pode conduzir (contratado, sem dívida de 3 dias, sem estar conduzindo)
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
                   + public.skill_effect('gerente', g.skills, 'lead_success_pts') + public.item_effect(g, 'expedition_success_pts_when_leading'),
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

create or replace function public.exp_capacity(v public.vehicles, p_lead jsonb)
returns int
language sql stable
set search_path = ''
as $$
  select floor((public.vehicle_def(v.vehicle_id) ->> 'capacity')::double precision * public.rarity_mult(v.rarity)
               * (1 + coalesce((p_lead ->> 'capacity_pct')::double precision, 0) / 100))::int
$$;

create or replace function public.exp_hours(v public.vehicles, p_route text, p_lead jsonb, fx jsonb)
returns double precision
language sql stable
set search_path = ''
as $$
  select (public.exp_route(p_route) ->> 'hours')::double precision * (public.vehicle_def(v.vehicle_id) ->> 'duration_multiplier')::double precision
         / public.rarity_mult(v.rarity) * coalesce((p_lead ->> 'duration_mult')::double precision, 1)
         * (1 + coalesce((fx ->> 'exp_duration')::double precision, 0))
$$;

-- chance de sucesso fixada na saída (teto de 95%)
create or replace function public.exp_chance(p_user uuid, v public.vehicles, p_route text, p_lead jsonb, p_minigame text, fx jsonb)
returns double precision
language sql stable
set search_path = ''
as $$
  with e as (select public.config_get('expeditions') c)
  select greatest(0, least((c ->> 'success_cap')::double precision,
    (public.exp_route(p_route) ->> 'success')::double precision
    + ((public.vehicle_def(v.vehicle_id) ->> 'safety_pts')::double precision * public.rarity_mult(v.rarity)
       + coalesce((c -> 'minigame' -> 'result_pts' ->> p_minigame)::double precision, 0)
       + coalesce((p_lead ->> 'success_pts')::double precision, 0)
       + coalesce((fx ->> 'exp_success')::double precision, 0)
       + case when v.durability < (c ->> 'low_wear_threshold_pct')::double precision then (c ->> 'low_wear_success_pts')::double precision else 0 end
       + case when (select exp_fail_streak from public.farms where user_id = p_user) >= (c -> 'bad_luck_protection' ->> 'after_failures')::int
              then (c -> 'bad_luck_protection' ->> 'bonus_pts')::double precision else 0 end) / 100))
  from e
$$;

-- valor da carga a preço da rota, com +20% nos produtos da demanda do dia
create or replace function public.exp_cargo_value(p_cargo jsonb, p_route text, p_day date)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce(round(sum(c.value::numeric * public.item_price(c.key) * (public.exp_route(p_route) ->> 'price_multiplier')::numeric
           * case when c.key = any (public.demand_of(p_day, p_route)) then 1 + (public.config_get('expeditions') -> 'daily_demand' ->> 'bonus')::numeric else 1 end), 2), 0)
  from jsonb_each_text(p_cargo) c
$$;

-- tira a carga do Silo (confere a quantidade)
create or replace function public.exp_take_cargo(p_user uuid, p_cargo jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare c record;
begin
  for c in select key, value::int q from jsonb_each_text(p_cargo) loop
    if c.q <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
    if public.item_price(c.key) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
    update public.silo set qty = qty - c.q where user_id = p_user and item_id = c.key and qty >= c.q;
    if not found then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  end loop;
end;
$$;

-- devolve itens ao Silo
create or replace function public.silo_add(p_user uuid, p_items jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.silo (user_id, item_id, qty) select p_user, key, value::int from jsonb_each_text(p_items) where value::int > 0
  on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty
$$;

-- uma viagem sai: desgaste, seguro (já validado), linha da expedição
create or replace function public.exp_depart(p_user uuid, p_convoy uuid, v public.vehicles, p_route text, p_cargo jsonb, p_insured boolean,
  p_lead jsonb, p_minigame text, p_t double precision, p_seq int, p_repeat_left int, fx jsonb, p_gold_left numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
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
      started_at, returns_at, seq, repeat_left)
    values (p_user, p_convoy, v.vehicle_id, p_route, p_cargo, v_value, v_dem, v_ins, p_lead is not null, p_minigame,
      public.exp_chance(p_user, v, p_route, p_lead, p_minigame, fx), p_t, p_t + public.exp_hours(v, p_route, p_lead, fx) * 3600, p_seq, p_repeat_left);
  update public.vehicles set durability = greatest(0, durability - (e ->> 'wear_per_trip_pct')::double precision * (1 + coalesce((fx ->> 'vehicle_wear')::double precision, 0)))
    where user_id = p_user and vehicle_id = v.vehicle_id;
  if v_ins > 0 then
    perform public.ledger_post(p_user, -v_ins, 'exp_insurance', jsonb_build_object('convoy', p_convoy, 'vehicle', v.vehicle_id, 'route', p_route, 'seq', p_seq));
  end if;
  return v_ins;
end;
$$;

-- sorteio na volta (a chance foi fixada na saída) e relatório narrado
create or replace function public.exp_resolve(p_id uuid, fx jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  x public.expeditions; e jsonb := public.config_get('expeditions'); r jsonb; lead jsonb; u double precision; pc double precision;
  v_out text; v_gold numeric := 0; v_refund numeric := 0; v_loss double precision; v_back jsonb := '{}'; v_drops jsonb := '[]';
  v_rolls int := 1; k int; c record; v_lost int; v_rec boolean := false; v_txt text; v_items jsonb;
begin
  select * into x from public.expeditions where id = p_id for update;
  r := public.exp_route(x.route_id);
  if x.led then lead := public.lead_info(x.user_id); end if;
  u := public.rand01();
  pc := least(x.chance, (e -> 'crit' ->> 'chance')::double precision + coalesce((lead ->> 'crit_pts')::double precision, 0) / 100);
  if u < pc then v_out := 'crit'; elsif u < x.chance then v_out := 'success'; else v_out := 'fail'; end if;

  if v_out = 'crit' then
    v_gold := round(x.cargo_value * (1 + (e -> 'crit' ->> 'bonus_value')::numeric) * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
    v_rolls := (e -> 'crit' ->> 'item_rolls')::int;
  elsif v_out = 'success' then
    v_gold := round(x.cargo_value * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
  else
    v_loss := ((r -> 'loss' ->> 0)::double precision + public.rand01() * ((r -> 'loss' ->> 1)::double precision - (r -> 'loss' ->> 0)::double precision))
              * (1 + coalesce((lead ->> 'loss_pct')::double precision, 0) / 100);
    v_loss := greatest(0, least(1, v_loss));
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

  -- prêmios: item (vestimenta ou amuleto), Escritura e Kit de Reforma
  v_items := (public.config_get('tools_and_items') -> 'clothing_cards') || (public.config_get('tools_and_items') -> 'amulet_cards');
  for k in 1 .. v_rolls loop
    if public.rand01() < (r ->> 'item_chance')::double precision * (1 + coalesce((lead ->> 'item_pct')::double precision, 0) / 100) then
      v_drops := v_drops || to_jsonb((v_items -> floor(public.rand01() * jsonb_array_length(v_items))::int ->> 'id') || ':' || public.pick_rarity(r -> 'item_rarity'));
    end if;
  end loop;
  if public.rand01() < (r ->> 'deed_chance')::double precision * (1 + coalesce((lead ->> 'deed_pct')::double precision, 0) / 100) then
    v_drops := v_drops || to_jsonb('deed'::text);
  end if;
  if public.rand01() < (r ->> 'kit_chance')::double precision then
    v_drops := v_drops || to_jsonb('kit:' || public.pick_rarity(r -> 'kit_rarity'));
  end if;

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
$$;

-- viagens que voltaram até o tempo t: sorteia, sai a repetição (mesmos produtos, até a capacidade), solta o Gerente;
-- termina reformas; garante a demanda de hoje e de amanhã
create or replace function public.process_expeditions(p_user uuid, p_t double precision)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  x public.expeditions; v public.vehicles; fx jsonb; lead jsonb; v_cargo jsonb; v_cap int; v_left int; c record; v_take int;
  v_gold numeric; i int := 0;
begin
  perform public.demand_ensure(public.game_day(now()));
  perform public.demand_ensure(public.game_day(now()) + 1);
  update public.vehicles set rarity = refurb_rarity, refurb_rarity = null, refurb_until = null
    where user_id = p_user and refurb_until is not null and refurb_until <= p_t;
  if not exists (select 1 from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t) then return; end if;
  fx := public.team_fx(p_user);
  loop
    i := i + 1; exit when i > 200;
    select * into x from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t order by returns_at, id limit 1;
    exit when not found;
    perform public.exp_resolve(x.id, fx);
    if x.repeat_left > 0 then
      -- repetição: mesmos produtos da viagem, até a capacidade, com o que houver no Silo
      select * into v from public.vehicles where user_id = p_user and vehicle_id = x.vehicle_id;
      lead := case when x.led then public.lead_info(p_user) else null end;
      v_cap := public.exp_capacity(v, lead); v_left := v_cap; v_cargo := '{}';
      for c in select key, value::int q from jsonb_each_text(x.cargo) order by value::int desc, key loop
        select least(coalesce(max(qty), 0), v_left) into v_take from public.silo where user_id = p_user and item_id = c.key;
        if v_take > 0 then v_cargo := v_cargo || jsonb_build_object(c.key, v_take); v_left := v_left - v_take; end if;
      end loop;
      if v_cargo <> '{}'::jsonb then
        perform public.exp_take_cargo(p_user, v_cargo);
        select gold into v_gold from public.wallets where user_id = p_user;
        perform public.exp_depart(p_user, x.convoy_id, v, x.route_id, v_cargo, x.insurance > 0, lead, x.minigame, x.returns_at,
          x.seq + 1, x.repeat_left - 1, fx, v_gold);
      end if;
    end if;
    -- o Gerente volta quando nenhum veículo que ele conduz está viajando
    if x.led and not exists (select 1 from public.expeditions where user_id = p_user and convoy_id = x.convoy_id and led and status = 'travel') then
      update public.characters set leading_id = null where user_id = p_user and class_id = 'gerente' and leading_id = x.convoy_id;
    end if;
  end loop;
end;
$$;

-- avalia o minigame: setas na ordem, erro custa 0,5 s; o tempo final nunca é menor que o relógio do servidor
-- (menos a tolerância de rede); intervalos rápidos demais ou sempre iguais = robô (vale no máximo "Concluída")
create or replace function public.minigame_eval(mg public.minigames, p_keys jsonb)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  m jsonb := public.config_get('expeditions') -> 'minigame'; n int := array_length(mg.arrows, 1);
  pos int := 0; errs int := 0; last_t double precision := 0; prev double precision; k record; iv double precision[] := '{}';
  fin double precision; real_ms double precision := extract(epoch from (now() - mg.started_at)) * 1000; res text; robot boolean := false;
begin
  for k in select x ->> 'k' key, (x ->> 't')::double precision t from jsonb_array_elements(coalesce(p_keys, '[]')) with ordinality a(x, o) order by o loop
    exit when pos >= n;
    if prev is not null then iv := iv || (k.t - prev); end if;
    prev := k.t;
    if k.key = mg.arrows[pos + 1] then pos := pos + 1; last_t := k.t; else errs := errs + 1; end if;
  end loop;
  if array_length(iv, 1) >= 1 and (select min(z) from unnest(iv) z) < (m ->> 'min_interval_ms')::double precision then robot := true; end if;
  if array_length(iv, 1) >= 3 and (select max(z) - min(z) from unnest(iv) z) < 5 then robot := true; end if;
  if pos = n then
    fin := greatest(last_t + errs * (m ->> 'wrong_key_penalty_s')::double precision * 1000, real_ms - (m ->> 'tolerance_ms')::double precision);
    if fin <= mg.limit_ms then
      res := case when errs = 0 and not mg.calm and fin <= mg.limit_ms * (1 - (m ->> 'perfect_time_left')::double precision) then 'perfect' else 'done' end;
    end if;
  end if;
  if res is null then
    res := case when pos >= n * (m ->> 'incomplete_min_fraction')::double precision then 'incomplete' else 'failed' end;
  end if;
  if robot and res = 'perfect' then res := 'done'; end if;
  return jsonb_build_object('result', res, 'robot', robot, 'errors', errs, 'done', pos, 'of', n, 'finish_ms', round(coalesce(fin, real_ms)));
end;
$$;

-- estado das expedições para a tela (sem o sorteio das viagens que ainda não foram recebidas)
create or replace function public.exp_state(p_user uuid)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'vehicles', (select coalesce(jsonb_agg(jsonb_build_object('vehicle_id', v.vehicle_id, 'rarity', v.rarity, 'durability', round(v.durability::numeric, 2),
        'active', v.active, 'refurb_rarity', v.refurb_rarity, 'refurb_until', v.refurb_until) order by v.bought_at), '[]')
      from public.vehicles v where v.user_id = p_user),
    'expeditions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'convoy_id', x.convoy_id, 'vehicle_id', x.vehicle_id, 'route_id', x.route_id,
        'cargo', x.cargo, 'insurance', x.insurance, 'led', x.led, 'minigame', x.minigame, 'started_at', x.started_at, 'returns_at', x.returns_at,
        'seq', x.seq, 'repeat_left', x.repeat_left, 'status', x.status) order by x.started_at), '[]')
      from public.expeditions x where x.user_id = p_user and x.status in ('travel', 'back')),
    'exp_fail_streak', (select exp_fail_streak from public.farms where user_id = p_user),
    'lead', public.lead_info(p_user),
    'demand', (select coalesce(jsonb_object_agg(d.route_id, d.products), '{}') from public.daily_demand d where d.day = public.game_day(now())),
    'demand_tomorrow', case when (public.team_fx(p_user) ->> 'route_preview')::double precision > 0
      then (select coalesce(jsonb_object_agg(d.route_id, d.products), '{}') from public.daily_demand d where d.day = public.game_day(now()) + 1) end)
$$;

-- ---------- ações do jogo ----------
-- começa o minigame: o servidor sorteia as setas e marca a hora
create or replace function public.start_minigame(p_route text, p_vehicles int, p_manager boolean, p_calm boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); m jsonb := public.config_get('expeditions') -> 'minigame'; n int; secs double precision; arr text[]; k int; v_id uuid;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.exp_route(p_route) is null then raise exception 'rota não existe' using errcode = 'check_violation'; end if;
  if p_vehicles is null or p_vehicles < 1 or p_vehicles > 4 then raise exception 'número de veículos inválido' using errcode = 'check_violation'; end if;
  n := (m -> 'arrows' ->> p_route)::int + (m ->> 'convoy_extra_arrows')::int * (p_vehicles - 1);
  secs := (m -> 'seconds' ->> p_route)::double precision + (m ->> 'convoy_extra_seconds')::double precision * (p_vehicles - 1)
          + case when coalesce(p_manager, false) then (m ->> 'manager_extra_seconds')::double precision else 0 end;
  if coalesce(p_calm, false) then secs := secs * (m ->> 'calm_mode_time_multiplier')::double precision; end if;
  for k in 1 .. n loop
    arr := arr || ((m -> 'arrows_pool') ->> floor(public.rand01() * jsonb_array_length(m -> 'arrows_pool'))::int);
  end loop;
  insert into public.minigames (user_id, route_id, vehicles, manager, calm, arrows, limit_ms)
    values (v_user, p_route, p_vehicles, coalesce(p_manager, false), coalesce(p_calm, false), arr, round(secs * 1000)::int)
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'arrows', to_jsonb(arr), 'limit_ms', round(secs * 1000)::int);
end;
$$;

-- lança a expedição (1 veículo ou comboio): confere o minigame, divide a carga pela capacidade, cobra o seguro
create or replace function public.launch_expedition(p_minigame uuid, p_keys jsonb, p_vehicles text[], p_route text, p_cargo jsonb,
  p_insurance boolean, p_manager boolean, p_repeat boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); e jsonb := public.config_get('expeditions'); r jsonb := public.exp_route(p_route);
  mg public.minigames; ev jsonb; v public.vehicles; lead jsonb; fx jsonb; v_time double precision; v_level int; v_convoy uuid := gen_random_uuid();
  v_vid text; v_n int := 0; v_led int := 0; v_cap int; v_part jsonb; v_rest jsonb; c record; v_take int; v_total int; v_gold numeric; v_ins numeric;
  v_idx int; v_used int; v_value numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if r is null then raise exception 'rota não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select * into mg from public.minigames where id = p_minigame and user_id = v_user for update;
  if not found or mg.used then raise exception 'minigame inválido' using errcode = 'check_violation'; end if;
  if mg.route_id <> p_route or mg.vehicles <> coalesce(array_length(p_vehicles, 1), 0) or mg.manager <> coalesce(p_manager, false) then
    raise exception 'minigame não confere com a expedição' using errcode = 'check_violation';
  end if;
  update public.minigames set used = true where id = mg.id;
  -- partida velha demais (abandonada) conta como Falhou
  if now() - mg.started_at > make_interval(secs => (e -> 'minigame' ->> 'start_valid_s')::double precision + mg.limit_ms / 1000.0) then
    ev := jsonb_build_object('result', 'failed', 'robot', false);
  else
    ev := public.minigame_eval(mg, p_keys);
  end if;
  if (ev ->> 'robot')::boolean then
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (v_user, 'cheat.minigame_robot', v_user, jsonb_build_object('minigame', mg.id, 'keys', p_keys, 'eval', ev));
  end if;

  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if (r ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente para a rota' using errcode = 'check_violation'; end if;
  if p_insurance and r ->> 'insurance_pct' is null then raise exception 'essa rota não tem seguro' using errcode = 'check_violation'; end if;
  if p_cargo is null or p_cargo = '{}'::jsonb then raise exception 'escolha a carga' using errcode = 'check_violation'; end if;
  if coalesce(p_manager, false) then
    lead := public.lead_info(v_user);
    if lead is null or not (lead ->> 'available')::boolean then raise exception 'o Gerente não pode conduzir agora' using errcode = 'check_violation'; end if;
  end if;
  fx := public.team_fx(v_user);
  perform public.exp_take_cargo(v_user, p_cargo);
  v_rest := p_cargo;

  foreach v_vid in array p_vehicles loop
    v_n := v_n + 1;
    select * into v from public.vehicles where user_id = v_user and vehicle_id = v_vid for update;
    if not found then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
    if v.refurb_until is not null then raise exception 'veículo na reforma' using errcode = 'check_violation'; end if;
    if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = v_vid and status in ('travel', 'back')) then
      raise exception 'veículo ocupado (viajando ou esperando Receber)' using errcode = 'check_violation';
    end if;
    if public.exp_route_idx(p_route) > public.exp_route_idx(public.vehicle_def(v_vid) ->> 'max_route') then
      raise exception 'esse veículo não vai até essa rota' using errcode = 'check_violation';
    end if;
    -- a carga enche os veículos na ordem escolhida
    v_cap := public.exp_capacity(v, case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then lead end);
    v_part := '{}'; v_used := 0;
    for c in select key, value::int q from jsonb_each_text(v_rest) where value::int > 0 order by key loop
      v_take := least(c.q, v_cap - v_used);
      exit when v_take <= 0;
      v_part := v_part || jsonb_build_object(c.key, v_take);
      v_rest := v_rest || jsonb_build_object(c.key, c.q - v_take);
      v_used := v_used + v_take;
    end loop;
    if v_used = 0 then raise exception 'carga vazia para um dos veículos' using errcode = 'check_violation'; end if;
    select gold into v_gold from public.wallets where user_id = v_user;
    if coalesce(p_insurance, false) then
      v_value := public.exp_cargo_value(v_part, p_route, public.game_day(now()));
      v_ins := round(v_value * (r ->> 'insurance_pct')::numeric / 100
               * (1 + case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then (lead ->> 'insurance_pct')::numeric else 0 end / 100), 2);
      if v_ins > v_gold then raise exception 'ouro insuficiente para o seguro' using errcode = 'check_violation'; end if;
    end if;
    perform public.exp_depart(v_user, v_convoy, v, p_route, v_part,
      coalesce(p_insurance, false), case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then lead end,
      ev ->> 'result', v_time, 0, case when coalesce(p_repeat, false) then (e ->> 'auto_repeat_max')::int else 0 end, fx, v_gold);
    if coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then v_led := v_led + 1; end if;
  end loop;
  select coalesce(sum(value::int), 0) into v_total from jsonb_each_text(v_rest);
  if v_total > 0 then raise exception 'carga maior que a capacidade' using errcode = 'check_violation'; end if;
  if v_led > 0 then update public.characters set leading_id = v_convoy where user_id = v_user and class_id = 'gerente'; end if;
  update public.vehicles set active = (vehicle_id = p_vehicles[1]) where user_id = v_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'expedition.launched', v_user, jsonb_build_object('convoy', v_convoy, 'route', p_route, 'vehicles', p_vehicles,
      'cargo', p_cargo, 'insurance', p_insurance, 'manager', p_manager, 'minigame', ev));
  return public.farm_state(v_user) || jsonb_build_object('minigame', ev);
end;
$$;

-- Receber: ouro, devolução do seguro, carga que voltou e prêmios das viagens que já voltaram
create or replace function public.collect_expeditions(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); x public.expeditions; d text; v_list jsonb := '[]';
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
    for d in select jsonb_array_elements_text(x.drops) loop
      insert into public.inventory (user_id, item_id, qty) values (v_user, d, 1)
        on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
    end loop;
    update public.expeditions set status = 'collected', collected_at = now() where id = x.id;
    v_list := v_list || jsonb_build_object('id', x.id, 'vehicle_id', x.vehicle_id, 'route_id', x.route_id, 'seq', x.seq, 'outcome', x.outcome,
      'gold', x.gold, 'refund', x.refund, 'cargo', x.cargo, 'cargo_back', x.cargo_back, 'loss_frac', x.loss_frac, 'drops', x.drops,
      'report', x.report, 'insurance', x.insurance, 'minigame', x.minigame, 'chance', round(x.chance::numeric, 4));
  end loop;
  if v_list = '[]'::jsonb then raise exception 'nada para receber' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user) || jsonb_build_object('collected', v_list);
end;
$$;

create or replace function public.buy_vehicle(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); d jsonb := public.vehicle_def(p_vehicle); v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if d is null then raise exception 'veículo não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select level into v_level from public.farms where user_id = v_user;
  if (d ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.vehicles where user_id = v_user and vehicle_id = p_vehicle) then raise exception 'você já tem esse veículo' using errcode = 'check_violation'; end if;
  perform public.ledger_post(v_user, -(d ->> 'cost')::numeric, 'vehicle_buy', jsonb_build_object('vehicle', p_vehicle), 'vehicle:' || p_vehicle);
  update public.vehicles set active = false where user_id = v_user;
  insert into public.vehicles (user_id, vehicle_id, active) values (v_user, p_vehicle, true);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'vehicle.bought', v_user, jsonb_build_object('vehicle', p_vehicle, 'cost', d -> 'cost'));
  return public.farm_state(v_user);
end;
$$;

create or replace function public.set_active_vehicle(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.vehicles where user_id = v_user and vehicle_id = p_vehicle) then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  update public.vehicles set active = (vehicle_id = p_vehicle) where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;

-- reforma na Forja: ouro + 1 Kit da raridade nova; o veículo fica parado o tempo da reforma
create or replace function public.refurbish_vehicle(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); v public.vehicles; nx jsonb; v_level int; v_time double precision; v_cost numeric; v_kit text;
  tiers text[] := array['common', 'uncommon', 'rare', 'legendary', 'mythic'];
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into v from public.vehicles where user_id = v_user and vehicle_id = p_vehicle for update;
  if not found then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
  if v.refurb_until is not null then raise exception 'veículo já está na reforma' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = p_vehicle and status in ('travel', 'back')) then
    raise exception 'veículo ocupado (viajando ou esperando Receber)' using errcode = 'check_violation';
  end if;
  if v.rarity = 'mythic' then raise exception 'veículo já é Mítico' using errcode = 'check_violation'; end if;
  select x into nx from jsonb_array_elements(public.config_get('expeditions') -> 'refurbish') x where x ->> 'rarity' = tiers[array_position(tiers, v.rarity) + 1];
  select level, farm_time into v_level, v_time from public.farms where user_id = v_user;
  if v_level < (nx ->> 'min_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_kit := 'kit:' || (nx ->> 'rarity');
  update public.inventory set qty = qty - 1 where user_id = v_user and item_id = v_kit and qty >= 1;
  if not found then raise exception 'falta o Kit de Reforma' using errcode = 'check_violation'; end if;
  v_cost := round(public.vehicle_price(p_vehicle) * (nx ->> 'cost_ratio')::numeric, 2);
  perform public.ledger_post(v_user, -v_cost, 'vehicle_refurbish', jsonb_build_object('vehicle', p_vehicle, 'rarity', nx ->> 'rarity'),
    'refurb:' || p_vehicle || ':' || (nx ->> 'rarity'));
  update public.vehicles set refurb_rarity = nx ->> 'rarity', refurb_until = v_time + (nx ->> 'hours')::double precision * 3600
    where user_id = v_user and vehicle_id = p_vehicle;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'vehicle.refurbish', v_user, jsonb_build_object('vehicle', p_vehicle, 'rarity', nx ->> 'rarity', 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;

-- conserto: proporcional ao que falta (10% do preço do veículo de 0 a 100%)
create or replace function public.repair_vehicle(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v public.vehicles; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into v from public.vehicles where user_id = v_user and vehicle_id = p_vehicle for update;
  if not found then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
  if v.durability >= 100 then raise exception 'veículo já está inteiro' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = p_vehicle and status = 'travel') then
    raise exception 'veículo está viajando' using errcode = 'check_violation';
  end if;
  v_cost := round(public.vehicle_price(p_vehicle) * (public.config_get('expeditions') -> 'vehicle_repair' ->> 'cost_ratio_of_price')::numeric
            * (100 - v.durability)::numeric / 100, 2);
  perform public.ledger_post(v_user, -v_cost, 'vehicle_repair', jsonb_build_object('vehicle', p_vehicle, 'durability', round(v.durability::numeric, 1)));
  update public.vehicles set durability = 100 where user_id = v_user and vehicle_id = p_vehicle;
  return public.farm_state(v_user);
end;
$$;

-- 3 iguais viram 1 da raridade acima (Kits de Reforma, vestimentas e amuletos)
create or replace function public.merge_items(p_item text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); tiers text[] := array['common', 'uncommon', 'rare', 'legendary', 'mythic'];
  v_base text := split_part(p_item, ':', 1); v_rar text := split_part(p_item, ':', 2); v_n int; v_next text;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not (v_base = 'kit' or public.equip_def(p_item) is not null) or array_position(tiers, v_rar) is null then
    raise exception 'item não pode ser juntado' using errcode = 'check_violation';
  end if;
  if v_rar = 'mythic' then raise exception 'já é Mítico' using errcode = 'check_violation'; end if;
  v_n := case when v_base = 'kit' then (public.config_get('expeditions') ->> 'kit_merge')::int
              else (public.config_get('tools_and_items') -> 'equipment_rarities' -> v_rar ->> 'merge_count_to_upgrade')::int end;
  perform public.touch_farm(v_user);
  update public.inventory set qty = qty - v_n where user_id = v_user and item_id = p_item and qty >= v_n;
  if not found then raise exception 'precisa de 3 iguais' using errcode = 'check_violation'; end if;
  v_next := v_base || ':' || tiers[array_position(tiers, v_rar) + 1];
  insert into public.inventory (user_id, item_id, qty) values (v_user, v_next, 1)
    on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'item.merged', v_user, jsonb_build_object('from', p_item, 'to', v_next, 'n', v_n));
  return public.farm_state(v_user);
end;
$$;

-- equipar vestimenta ou amuleto (p_item null tira o do espaço p_slot: 'cloth' ou 'amulet')
create or replace function public.equip_item(p_class text, p_slot text, p_item text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); c public.characters; v_old text;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_slot not in ('cloth', 'amulet') then raise exception 'espaço inválido' using errcode = 'check_violation'; end if;
  if p_item is not null and (public.equip_def(p_item) is null or split_part(p_item, '_', 1) <> p_slot) then
    raise exception 'item não serve nesse espaço' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found then raise exception 'personagem não contratado' using errcode = 'check_violation'; end if;
  v_old := case when p_slot = 'cloth' then c.cloth_id else c.amulet_id end;
  if p_item is not null then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = p_item and qty >= 1;
    if not found then raise exception 'item não está no inventário' using errcode = 'check_violation'; end if;
  end if;
  if v_old is not null then
    insert into public.inventory (user_id, item_id, qty) values (v_user, v_old, 1)
      on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
  end if;
  if p_slot = 'cloth' then update public.characters set cloth_id = p_item where user_id = v_user and class_id = p_class;
  else update public.characters set amulet_id = p_item where user_id = v_user and class_id = p_class; end if;
  return public.farm_state(v_user);
end;
$$;

-- admin: trazer de volta as viagens e terminar reformas (para testes), com justificativa e auditoria
create or replace function public.admin_finish_expeditions(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_time double precision; n int; m int;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  select farm_time into v_time from public.farms where user_id = p_user;
  update public.expeditions set returns_at = v_time where user_id = p_user and status = 'travel' and returns_at > v_time;
  get diagnostics n = row_count;
  update public.vehicles set refurb_until = v_time where user_id = p_user and refurb_until > v_time;
  get diagnostics m = row_count;
  if n + m = 0 then raise exception 'nenhuma viagem ou reforma em andamento' using errcode = 'check_violation'; end if;
  perform public.process_expeditions(p_user, v_time);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.finish_expeditions', p_user, jsonb_build_object('trips', n, 'refurbs', m, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- admin: dar itens (Escritura, Kit de Reforma, vestimenta e amuleto) para testes
create or replace function public.admin_grant_item(p_user uuid, p_item text, p_qty integer, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if not (p_item = 'deed'
          or (split_part(p_item, ':', 1) = 'kit' and split_part(p_item, ':', 2) in ('uncommon', 'rare', 'legendary', 'mythic'))
          or (public.equip_def(p_item) is not null and split_part(p_item, ':', 2) in ('common', 'uncommon', 'rare', 'legendary', 'mythic'))) then
    raise exception 'item desconhecido' using errcode = 'check_violation';
  end if;
  if p_qty is null or p_qty = 0 or abs(p_qty) > 10 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  insert into public.inventory (user_id, item_id, qty) values (p_user, p_item, greatest(p_qty, 0))
    on conflict (user_id, item_id) do update set qty = greatest(0, public.inventory.qty + p_qty);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_item', p_user, jsonb_build_object('item', p_item, 'qty', p_qty, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- a Carroça já vem na fazenda nova
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
  insert into public.vehicles (user_id, vehicle_id, active)
    select p_user, x ->> 'id', true from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x
    where (x ->> 'cost')::numeric = 0 limit 1
    on conflict do nothing;
end;
$$;

-- personagem ativo: em campo, sem 3 dias de dívida e sem estar conduzindo uma expedição
create or replace function public.char_active(c public.characters)
returns boolean
language sql stable
set search_path = ''
as $$
  select c.slot = 'field' and c.leading_id is null and c.unpaid_days < coalesce((public.config_get('characters') -> 'salary' ->> 'stops_after_days')::int, 3)
$$;

-- luvas: + capacidade de trabalho
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
       * (1 + public.skill_effect(c.class_id, c.skills, 'work_capacity_pct') / 100 + (fx ->> 'team_capacity')::double precision
          + public.item_effect(c, 'work_capacity_pct') / 100)
       * case when c.debt > 0 then (ch -> 'salary' ->> 'unpaid_efficiency')::double precision else 1 end
       * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 + (ch -> 'pets' ->> 'per_level_work_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end
  from cfg
$function$;

-- chapéu: + energia máxima; botas: − gasto de energia (dentro do teto)
create or replace function public.char_energy(c public.characters, fx jsonb)
returns jsonb
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + public.item_effect(c, 'max_energy_bonus'),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + public.skill_effect(c.class_id, c.skills, 'energy_use_pct') / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * (1 - public.item_effect(c, 'energy_cost_reduction_pct') / 100)
                           * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 - (ch -> 'pets' ->> 'per_level_energy_use_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') / 100)))
  from cfg
$$;

-- quem conduz não gasta nem recupera energia; Relógio de Bolso: + XP do personagem
CREATE OR REPLACE FUNCTION public.tick_team(p_user uuid, p_hours double precision, p_frac double precision, fx jsonb)
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
  v_today date := public.game_day(now()); s jsonb; worked double precision;
begin
  for c in select * from public.characters where user_id = p_user for update loop
    en := public.char_energy(c, fx);
    v_e := c.energy; v_h := c.work_hours; v_lvl := c.level; v_park := c.parked; v_qty := c.snack_qty; v_rev := c.revive_day;
    if c.leading_id is not null then
      null; -- conduzindo uma expedição: nem trabalha nem descansa
    elsif c.slot = 'field' and not c.parked and public.char_active(c) and c.energy > 0 then
      worked := p_hours * p_frac;
      v_e := v_e - (en ->> 'use')::double precision * worked;
      v_h := v_h + worked * (1 + public.item_effect(c, 'character_xp_pct') / 100); -- Relógio de Bolso
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
$function$;

-- quem conduz fica no slot até voltar (não entra nem sai no rodízio)
CREATE OR REPLACE FUNCTION public.rotate_team(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e jsonb := public.config_get('characters') -> 'energy';
  slots int := (public.config_get('characters') ->> 'field_slots')::int;
  c record; b record; n_field int;
begin
  if (select count(*) from public.characters where user_id = p_user) < (e ->> 'rotation_from_characters')::int then return; end if;
  for c in select ch.class_id, public.class_def(ch.class_id) ->> 'role' as role from public.characters ch
           where ch.user_id = p_user and ch.slot = 'field' and ch.leading_id is null and ch.energy <= (e ->> 'leave_field_at')::double precision order by ch.energy loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.leading_id is null and ch.energy >= (e ->> 'enter_field_at')::double precision
      order by (public.class_def(ch.class_id) ->> 'role' = c.role) desc, ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'bench', parked = false where user_id = p_user and class_id = c.class_id;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
  end loop;
  -- vaga livre no campo: entra quem está descansado
  select count(*) into n_field from public.characters where user_id = p_user and slot = 'field';
  while n_field < slots loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.leading_id is null and ch.energy >= (e ->> 'enter_field_at')::double precision order by ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
    n_field := n_field + 1;
  end loop;
end;
$function$;

-- ---------- efeitos da equipe (fase 5: expedições, Cachorro, amuletos) ----------
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
    'expansion_cost_pct', 'vehicle_wear_pct', 'expedition_success_pts', 'expedition_duration_pct', 'route_demand_preview'];
  caps jsonb := coalesce(public.config_get('cards') -> 'bonus_caps', '{}'::jsonb);
  cap_seed double precision := coalesce((caps -> 'seed_sapling_feed_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100;
  ranch boolean := false;
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0; gato_animal double precision := 0;
  dog_pts double precision := 0; dog_rec double precision := 0; it_double double precision := 0; it_animal double precision := 0;
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
  return jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100 + it_double),
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
    'animal_production', ((s ->> 'animal_production_pct')::double precision) / 100 + gato_animal + it_animal,
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
    'exp_success', (s ->> 'expedition_success_pts')::double precision + dog_pts,
    'exp_duration', (s ->> 'expedition_duration_pct')::double precision / 100,
    'vehicle_wear', (s ->> 'vehicle_wear_pct')::double precision / 100,
    'route_preview', (s ->> 'route_demand_preview')::double precision,
    'dog_recover', dog_rec,
    'pet', pet);
end;
$$;

-- ---------- avanço da fazenda (fase 5: expedições no fim) ----------
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
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
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
      'energy_rest', round((public.char_energy(ch, fx) ->> 'rest')::numeric, 3), 'active', public.char_active(ch), 'leading', ch.leading_id is not null,
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
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira',
        'exp_success', fx -> 'exp_success', 'exp_duration', fx -> 'exp_duration', 'vehicle_wear', fx -> 'vehicle_wear', 'dog_recover', fx -> 'dog_recover')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base || public.exp_state(p_user);
end;
$$;


-- ---------- permissões ----------
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.exp_route(text)', 'public.exp_route_idx(text)', 'public.vehicle_def(text)', 'public.vehicle_price(text)', 'public.equip_def(text)',
    'public.item_effect(public.characters, text)', 'public.pick_rarity(jsonb)', 'public.demand_ensure(date)', 'public.demand_of(date, text)',
    'public.lead_info(uuid)', 'public.exp_capacity(public.vehicles, jsonb)', 'public.exp_hours(public.vehicles, text, jsonb, jsonb)',
    'public.exp_chance(uuid, public.vehicles, text, jsonb, text, jsonb)', 'public.exp_cargo_value(jsonb, text, date)', 'public.exp_take_cargo(uuid, jsonb)',
    'public.silo_add(uuid, jsonb)',
    'public.exp_depart(uuid, uuid, public.vehicles, text, jsonb, boolean, jsonb, text, double precision, int, int, jsonb, numeric)',
    'public.exp_resolve(uuid, jsonb)', 'public.process_expeditions(uuid, double precision)', 'public.minigame_eval(public.minigames, jsonb)',
    'public.exp_state(uuid)', 'public.create_farm(uuid)', 'public.char_active(public.characters)',
    'public.char_rate(public.characters, text, double precision, jsonb)', 'public.char_energy(public.characters, jsonb)',
    'public.tick_team(uuid, double precision, double precision, jsonb)', 'public.rotate_team(uuid)', 'public.team_fx(uuid)',
    'public.advance_farm(uuid, timestamptz)', 'public.farm_state(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array[
    'public.start_minigame(text, int, boolean, boolean)', 'public.launch_expedition(uuid, jsonb, text[], text, jsonb, boolean, boolean, boolean)',
    'public.collect_expeditions(text)', 'public.buy_vehicle(text)', 'public.set_active_vehicle(text)', 'public.refurbish_vehicle(text)',
    'public.repair_vehicle(text)', 'public.merge_items(text)', 'public.equip_item(text, text, text)',
    'public.admin_finish_expeditions(uuid, text)', 'public.admin_grant_item(uuid, text, integer, text)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
