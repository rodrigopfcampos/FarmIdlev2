-- Fase 7: missões (5 diárias, 5 semanais), pacotes com garantia, 10 cartas em 5 raridades com número de série,
-- buffs de até 3 cartas, Armory com bônus permanente, fichário com ampliação e caixa de entrada, Colecionador da Vila.
-- Regras na GDD seção 11; números em config/missions.json e config/cards.json.

-- ---------- tabelas ----------
create table public.cards (
  serial bigint generated always as identity primary key,       -- número de série único (impede duplicação)
  user_id uuid not null references public.farms (user_id) on delete restrict,
  card_id text not null,
  rarity text not null check (rarity in ('common', 'uncommon', 'rare', 'legendary', 'mythic')),
  state text not null default 'binder' check (state in ('binder', 'inbox', 'armory', 'used', 'sold')),
  origin text not null,                                         -- daily_pack, weekly_3, weekly_5, admin
  inbox_until timestamptz,                                      -- fichário cheio: espera até aqui
  seen boolean not null default false,                          -- o jogador já viu a carta virar
  created_at timestamptz not null default now(),
  changed_at timestamptz not null default now()
);
create index cards_user_state on public.cards (user_id, state);

create table public.card_buffs (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  card_id text not null,
  rarity text not null,
  serial bigint not null,
  started_at timestamptz not null,
  ends_at timestamptz not null,
  coin_value numeric(18, 2) not null default 0,                 -- Moeda da Sorte: ouro juntado, pago no fim
  primary key (user_id, card_id)
);

create table public.armory (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  card_id text not null,
  rarity text not null,
  serial bigint not null,
  placed_at timestamptz not null default now(),
  primary key (user_id, card_id, rarity)
);

create table public.missions (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  kind text not null check (kind in ('daily', 'weekly')),
  period date not null,                                         -- dia (diária) ou segunda-feira (semanal), no fuso da conta
  slot integer not null,
  mission_id text not null,
  metric text not null,
  target numeric(18, 2) not null,
  progress numeric(18, 2) not null default 0,
  done_at timestamptz,
  reward jsonb not null default '{}',                           -- diária: ouro e XP fixados na hora do sorteio
  primary key (user_id, kind, period, slot)
);

create table public.mission_weeks (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  week date not null,
  daily_packs integer not null default 0,                       -- até 4 pacotes das diárias por semana
  weekly_rewards integer not null default 0,                    -- 1 = carta das 3 semanais; 2 = carta + Escritura das 5
  primary key (user_id, week)
);

alter table public.farms add column pity_rare integer not null default 0;       -- cartas sem Raro ou melhor
alter table public.farms add column pity_legendary integer not null default 0;  -- sem Lendário ou melhor
alter table public.farms add column pity_mythic integer not null default 0;     -- sem Mítico
alter table public.farms add column binder_slots integer not null default 60;
alter table public.farms add column prod_value_h numeric(18, 2);                 -- produção por hora (valor da Feira), média móvel
alter table public.farms add column prod_xp_h numeric(18, 2);                    -- XP por hora, média móvel
alter table public.farms add column prod_day date;
alter table public.farms add column prod_day_value numeric(18, 2) not null default 0;
alter table public.farms add column prod_day_xp numeric(18, 2) not null default 0;
alter table public.farms add column reroll_day date;                             -- dia em que usou a troca grátis
alter table public.farms add column daily_pack_day date;                          -- dia em que já ganhou o pacote das diárias
alter table public.farms add column event_credit timestamptz;                     -- último evento que contou para a missão
alter table public.expeditions add column card_fx jsonb not null default '{}';   -- Estrada Livre e Trevo: valem para quem parte no buff

alter table public.cards enable row level security;
alter table public.card_buffs enable row level security;
alter table public.armory enable row level security;
alter table public.missions enable row level security;
alter table public.mission_weeks enable row level security;
create policy cards_read_own on public.cards for select to authenticated using (user_id = (select auth.uid()));
create policy armory_read_own on public.armory for select to authenticated using (user_id = (select auth.uid()));
create policy missions_read_own on public.missions for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.cards, public.card_buffs, public.armory, public.missions, public.mission_weeks from anon, authenticated;

-- ---------- ajudantes das cartas ----------
create or replace function public.jnum(p jsonb, k text)
returns double precision language sql immutable set search_path = '' as $$
  select coalesce((p ->> k)::double precision, 0)
$$;

create or replace function public.card_def(p_card text)
returns jsonb language sql stable set search_path = '' as $$
  select x from jsonb_array_elements(public.config_get('cards') -> 'cards') x where x ->> 'id' = p_card
$$;

create or replace function public.rarity_rank(p_rarity text)
returns int language sql immutable set search_path = '' as $$
  select array_position(array['common', 'uncommon', 'rare', 'legendary', 'mythic'], p_rarity)
$$;

-- soma dos efeitos dos buffs ativos no instante e do Armory (parcial = Comum+Incomum+Raro; completo = as 5)
create or replace function public.card_fx(p_user uuid, p_at timestamptz)
returns jsonb language sql stable security definer set search_path = '' as $$
  with b as (
    select e.key, sum(e.value::double precision) v
    from public.card_buffs cb, jsonb_each_text(public.card_def(cb.card_id) -> 'buff_effects' -> cb.rarity) e
    where cb.user_id = p_user and cb.started_at <= p_at and cb.ends_at > p_at
    group by e.key
  ), lvl as (
    select a.card_id, count(*) n, bool_and(true) filter (where a.rarity in ('common', 'uncommon', 'rare')) part,
           count(*) filter (where a.rarity in ('common', 'uncommon', 'rare')) np
    from public.armory a where a.user_id = p_user group by a.card_id
  ), a as (
    select e.key, sum(e.value::double precision) v
    from lvl, jsonb_each_text(public.card_def(lvl.card_id) -> 'armory_bonus' -> case when lvl.n >= 5 then 'complete_gold' else 'partial_silver' end) e
    where lvl.n >= 5 or lvl.np >= 3
    group by e.key
  )
  select jsonb_build_object('buff', coalesce((select jsonb_object_agg(key, v) from b), '{}'),
                            'armory', coalesce((select jsonb_object_agg(key, v) from a), '{}'))
$$;

-- sorteio com garantia: Raro+ a cada 10, Lendário+ a cada 40, Mítico a cada 120 (contadores visíveis)
create or replace function public.draw_card(p_user uuid, p_origin text)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare
  g jsonb := public.config_get('cards') -> 'gacha'; f public.farms; u double precision; r text; acc double precision := 0; k text;
  floor_rank int := 1; tot double precision := 0; c jsonb; n int; v_serial bigint; v_state text := 'binder'; v_until timestamptz;
begin
  select * into f from public.farms where user_id = p_user for update;
  if f.pity_mythic + 1 >= (g -> 'pity_thresholds' ->> 'mythic')::int then floor_rank := 5;
  elsif f.pity_legendary + 1 >= (g -> 'pity_thresholds' ->> 'legendary_or_better')::int then floor_rank := 4;
  elsif f.pity_rare + 1 >= (g -> 'pity_thresholds' ->> 'rare_or_better')::int then floor_rank := 3; end if;
  -- chances da tabela, só com as raridades permitidas pela garantia (redistribuídas)
  for k in select key from jsonb_each_text(g -> 'base_rates') loop
    if public.rarity_rank(k) >= floor_rank then tot := tot + (g -> 'base_rates' ->> k)::double precision; end if;
  end loop;
  u := public.rand01() * tot;
  foreach k in array array['common', 'uncommon', 'rare', 'legendary', 'mythic'] loop
    if public.rarity_rank(k) >= floor_rank then
      acc := acc + (g -> 'base_rates' ->> k)::double precision; r := k;
      exit when u < acc;
    end if;
  end loop;
  c := public.config_get('cards') -> 'cards';
  n := jsonb_array_length(c);
  update public.farms set
      pity_rare = case when public.rarity_rank(r) >= 3 then 0 else pity_rare + 1 end,
      pity_legendary = case when public.rarity_rank(r) >= 4 then 0 else pity_legendary + 1 end,
      pity_mythic = case when r = 'mythic' then 0 else pity_mythic + 1 end
    where user_id = p_user;
  -- fichário cheio: a carta espera na caixa de entrada
  if (select count(*) from public.cards where user_id = p_user and state = 'binder') >= f.binder_slots then
    v_state := 'inbox';
    v_until := now() + make_interval(days => (public.config_get('cards') -> 'binder' ->> 'inbox_overflow_retention_days')::int);
  end if;
  insert into public.cards (user_id, card_id, rarity, state, origin, inbox_until)
    values (p_user, c -> floor(public.rand01() * n)::int ->> 'id', r, v_state, p_origin, v_until)
    returning serial into v_serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'card.drawn', p_user, jsonb_build_object('serial', v_serial, 'rarity', r, 'origin', p_origin, 'pity_floor', floor_rank, 'state', v_state));
  return v_serial;
end;
$$;

-- preço do Colecionador da Vila: metade do valor do buff, sobre o R do nível de quem vende
create or replace function public.collector_price(p_user uuid, p_rarity text)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(public.ref_income(f.level) * (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'collector_sell_reference_income_ratio')::numeric, 2)
  from public.farms f where f.user_id = p_user
$$;

-- caixa de entrada: entra no fichário quando abre espaço; depois de 7 dias o Colecionador compra sozinho
create or replace function public.cards_maintain(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare c public.cards; v_free int; v numeric;
begin
  for c in select * from public.cards where user_id = p_user and state = 'inbox' and inbox_until <= now() order by serial for update loop
    v := public.collector_price(p_user, c.rarity);
    update public.cards set state = 'sold', changed_at = now() where serial = c.serial;
    if v > 0 then perform public.ledger_post(p_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'auto', true), 'card:' || c.serial); end if;
  end loop;
  select f.binder_slots - (select count(*) from public.cards where user_id = p_user and state = 'binder') into v_free from public.farms f where f.user_id = p_user;
  if v_free > 0 then
    update public.cards set state = 'binder', inbox_until = null, changed_at = now()
      where serial in (select serial from public.cards where user_id = p_user and state = 'inbox' order by serial limit v_free);
  end if;
end;
$$;

-- fim dos buffs: paga a Moeda da Sorte e libera o slot
create or replace function public.buffs_expire(p_user uuid, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare b public.card_buffs;
begin
  for b in select * from public.card_buffs where user_id = p_user and ends_at <= p_at for update loop
    if b.coin_value > 0 then
      perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial);
    end if;
    delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  end loop;
end;
$$;

-- ---------- produção do jogador (média por hora), Moeda da Sorte e progresso das missões ----------
create or replace function public.prod_roll(p_user uuid, p_day date)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare f public.farms; w double precision := (public.config_get('missions') -> 'production_reference' ->> 'new_day_weight')::double precision;
begin
  select * into f from public.farms where user_id = p_user for update;
  if f.prod_day is not distinct from p_day then return; end if;
  if f.prod_day is not null and f.prod_day < p_day then
    update public.farms set
        prod_value_h = round((coalesce(prod_value_h, prod_day_value / 24) * (1 - w) + w * prod_day_value / 24)::numeric, 2),
        prod_xp_h = round((coalesce(prod_xp_h, prod_day_xp / 24) * (1 - w) + w * prod_day_xp / 24)::numeric, 2)
      where user_id = p_user;
  end if;
  update public.farms set prod_day = p_day, prod_day_value = 0, prod_day_xp = 0 where user_id = p_user;
end;
$$;

-- referência das metas: produção por hora do próprio jogador, com piso pelo R do nível
create or replace function public.prod_ref(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('missions') -> 'production_reference' pr), f as (select * from public.farms where user_id = p_user)
  select jsonb_build_object(
    'value_h', greatest(coalesce(f.prod_value_h, public.ref_income(f.level) * (pr ->> 'initial_value_R_ratio_per_hour')::numeric),
                        public.ref_income(f.level) / 24 * (pr ->> 'floor_R_ratio')::numeric),
    'xp_h', greatest(coalesce(f.prod_xp_h, 0),
                     coalesce((public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric, 0) * (pr ->> 'initial_xp_per_hour_of_xp_to_next')::numeric
                       * case when f.prod_xp_h is null then 1 else (pr ->> 'floor_R_ratio')::numeric end))
  from f, c
$$;

-- arredonda a meta para 2 algarismos (2.480 → 2.500)
create or replace function public.nice_round(p numeric)
returns numeric language sql immutable set search_path = '' as $$
  select case when p <= 0 then 0 else round(p / power(10, floor(log(p)) - 1)) * power(10, floor(log(p)) - 1) end
$$;

create or replace function public.mission_week(p_day date)
returns date language sql immutable set search_path = '' as $$
  select p_day - (extract(isodow from p_day)::int - 1)
$$;

-- sorteia as missões do dia e da semana que ainda não existem (só sistemas já liberados)
create or replace function public.mission_ensure(p_user uuid, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  cfg jsonb := public.config_get('missions'); d date := public.user_day(p_user, p_at); w date; k text; per date; ref jsonb; m record; i int;
  v_level int; n_animals int; n_chars int; worn boolean; far boolean;
begin
  w := public.mission_week(d);
  if exists (select 1 from public.missions where user_id = p_user and kind = 'daily' and period = d)
     and exists (select 1 from public.missions where user_id = p_user and kind = 'weekly' and period = w) then return; end if;
  perform public.prod_roll(p_user, d);
  select level into v_level from public.farms where user_id = p_user;
  select count(*) into n_animals from public.animals where user_id = p_user;
  select count(*) into n_chars from public.characters where user_id = p_user;
  worn := exists (select 1 from public.vehicles where user_id = p_user and durability < (cfg ->> 'worn_vehicle_below_pct')::double precision);
  far := v_level >= coalesce((public.exp_route(cfg ->> 'far_route') ->> 'unlock_level')::int, 999);
  ref := public.prod_ref(p_user);
  foreach k in array array['daily', 'weekly'] loop
    per := case when k = 'daily' then d else w end;
    continue when exists (select 1 from public.missions where user_id = p_user and kind = k and period = per);
    i := 0;
    for m in
      select x from jsonb_array_elements(cfg -> 'bank' -> k) x
      where coalesce(x ->> 'gate', '') = '' or (x ->> 'gate' = 'animals' and n_animals > 0) or (x ->> 'gate' = 'chars3' and n_chars >= 3)
            or (x ->> 'gate' = 'worn_vehicle' and worn) or (x ->> 'gate' = 'capital' and far)
      order by public.rand01()
      limit (cfg -> k ->> 'count')::int
    loop
      i := i + 1;
      insert into public.missions (user_id, kind, period, slot, mission_id, metric, target, reward)
        values (p_user, k, per, i, m.x ->> 'id', m.x ->> 'metric', public.mission_target(m.x -> 'target', ref, n_animals),
          case when k = 'daily' then jsonb_build_object(
            'gold', round((cfg -> 'daily' ->> 'gold_hours_of_income')::numeric * (ref ->> 'value_h')::numeric, 2),
            'xp', round((cfg -> 'daily' ->> 'xp_hours_of_production')::numeric * (ref ->> 'xp_h')::numeric, 2)) else '{}' end)
        on conflict do nothing;
    end loop;
    insert into public.mission_weeks (user_id, week) values (p_user, w) on conflict do nothing;
  end loop;
end;
$$;

create or replace function public.mission_target(p_target jsonb, p_ref jsonb, p_animals int)
returns numeric language sql stable set search_path = '' as $$
  select case p_target ->> 'type'
    when 'hours_value' then greatest(1, public.nice_round((p_target ->> 'hours')::numeric * coalesce((p_target ->> 'mult')::numeric, 1) * (p_ref ->> 'value_h')::numeric))
    when 'hours_xp' then greatest(1, public.nice_round((p_target ->> 'hours')::numeric * (p_ref ->> 'xp_h')::numeric))
    when 'animals' then greatest((p_target ->> 'min')::numeric, (p_target ->> 'per_animal')::numeric * p_animals)
    else (p_target ->> 'n')::numeric end
$$;

-- avança as missões do período do instante; ao completar paga a diária e entrega pacote e cartas
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
      -- as 5 do dia: 1 pacote (até 4 por semana)
      if not exists (select 1 from public.missions where user_id = p_user and kind = 'daily' and period = d and done_at is null)
         and (select daily_pack_day from public.farms where user_id = p_user) is distinct from d then
        select * into wk from public.mission_weeks where user_id = p_user and week = w for update;
        if wk.daily_packs < (cfg -> 'daily' ->> 'max_packs_per_week')::int then
          update public.mission_weeks set daily_packs = daily_packs + 1 where user_id = p_user and week = w;
          update public.farms set daily_pack_day = d where user_id = p_user;
          perform public.draw_card(p_user, 'daily_pack');
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
        insert into public.inventory (user_id, item_id, qty) values (p_user, 'deed', (cfg -> 'weekly' ->> 'deed_at_5')::int)
          on conflict (user_id, item_id) do update set qty = public.inventory.qty + excluded.qty;
      end if;
    end if;
  end loop;
end;
$$;

-- tudo o que a fazenda produz: média de produção, Moeda da Sorte e missões de colheita e de animais
create or replace function public.produced(p_user uuid, p_item text, p_qty numeric, p_xp numeric, p_kind text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v numeric := coalesce(p_qty, 0) * coalesce(public.item_price(p_item), 0); at timestamptz := public.fx_at();
begin
  if coalesce(p_qty, 0) <= 0 then return; end if;
  perform public.prod_roll(p_user, public.user_day(p_user, at));
  update public.farms set prod_day_value = prod_day_value + v, prod_day_xp = prod_day_xp + coalesce(p_xp, 0) where user_id = p_user;
  -- Moeda da Sorte: % do valor do que foi produzido durante o buff
  update public.card_buffs set coin_value = coin_value + round(v * (public.card_def(card_id) -> 'buff_effects' -> rarity ->> 'production_gold_bonus_pct')::numeric / 100, 2)
    where user_id = p_user and started_at <= at and ends_at > at and public.card_def(card_id) -> 'buff_effects' -> rarity ? 'production_gold_bonus_pct';
  perform public.mission_progress(p_user, 'xp_earned', p_xp);
  if p_kind = 'animal' then perform public.mission_progress(p_user, 'animal_products', p_qty);
  else perform public.mission_progress(p_user, 'harvest_value', v); end if;
end;
$$;

-- ---------- ações do jogador ----------
create or replace function public.use_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; b public.card_buffs; cfg jsonb := public.config_get('cards');
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  select * into b from public.card_buffs where user_id = v_user and card_id = c.card_id;
  if found then
    -- a mesma carta só troca o buff com raridade igual ou maior, e reinicia o tempo
    if public.rarity_rank(c.rarity) < public.rarity_rank(b.rarity) then raise exception 'raridade menor que a do buff ativo' using errcode = 'check_violation'; end if;
    if b.coin_value > 0 then
      perform public.ledger_post(v_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity, 'replaced', true), 'coin:' || b.serial);
    end if;
    delete from public.card_buffs where user_id = v_user and card_id = c.card_id;
  elsif (select count(*) from public.card_buffs where user_id = v_user) >= (cfg -> 'rules' ->> 'max_active_buffs')::int then
    raise exception 'já tem 3 buffs ativos' using errcode = 'check_violation';
  end if;
  insert into public.card_buffs (user_id, card_id, rarity, serial, started_at, ends_at)
    values (v_user, c.card_id, c.rarity, c.serial, now(), now() + make_interval(mins => (cfg -> 'rarities' -> c.rarity ->> 'duration_minutes')::int));
  update public.cards set state = 'used', seen = true, changed_at = now() where serial = c.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.used', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.armory_place(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.armory where user_id = v_user and card_id = c.card_id and rarity = c.rarity) then
    raise exception 'essa raridade já está no Armory' using errcode = 'check_violation';
  end if;
  insert into public.armory (user_id, card_id, rarity, serial) values (v_user, c.card_id, c.rarity, c.serial);
  update public.cards set state = 'armory', seen = true, changed_at = now() where serial = c.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.armory', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.sell_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v := public.collector_price(v_user, c.rarity);
  update public.cards set state = 'sold', seen = true, changed_at = now() where serial = c.serial;
  perform public.ledger_post(v_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity), 'card:' || c.serial);
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.binder_expand()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); b jsonb := public.config_get('cards') -> 'binder'; f public.farms; v numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  if f.binder_slots + (b ->> 'expansion_slots')::int > (b ->> 'max_slots')::int then raise exception 'fichário já está no máximo' using errcode = 'check_violation'; end if;
  v := round(public.ref_income(f.level) * (b ->> 'expansion_cost_reference_income_ratio')::numeric, 2);
  perform public.ledger_post(v_user, -v, 'binder_expand', jsonb_build_object('slots', f.binder_slots + (b ->> 'expansion_slots')::int));
  update public.farms set binder_slots = binder_slots + (b ->> 'expansion_slots')::int where user_id = v_user;
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.reroll_mission(p_slot int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); d date; m public.missions; x jsonb; ref jsonb; n_animals int; cfg jsonb := public.config_get('missions');
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  d := public.user_day(v_user, now());
  perform public.mission_ensure(v_user, now());
  if (select reroll_day from public.farms where user_id = v_user) is not distinct from d then
    raise exception 'a troca grátis de hoje já foi usada' using errcode = 'check_violation';
  end if;
  select * into m from public.missions where user_id = v_user and kind = 'daily' and period = d and slot = p_slot for update;
  if not found or m.done_at is not null then raise exception 'missão não pode ser trocada' using errcode = 'check_violation'; end if;
  select count(*) into n_animals from public.animals where user_id = v_user;
  -- outra missão liberada que não esteja na lista de hoje (mesmas regras do sorteio)
  select y into x from jsonb_array_elements(cfg -> 'bank' -> 'daily') y
    where y ->> 'id' not in (select mission_id from public.missions where user_id = v_user and kind = 'daily' and period = d)
      and (coalesce(y ->> 'gate', '') = '' or (y ->> 'gate' = 'animals' and n_animals > 0)
           or (y ->> 'gate' = 'chars3' and (select count(*) from public.characters where user_id = v_user) >= 3)
           or (y ->> 'gate' = 'worn_vehicle' and exists (select 1 from public.vehicles where user_id = v_user and durability < (cfg ->> 'worn_vehicle_below_pct')::double precision)))
    order by public.rand01() limit 1;
  if x is null then raise exception 'não há outra missão disponível' using errcode = 'check_violation'; end if;
  ref := public.prod_ref(v_user);
  update public.missions set mission_id = x ->> 'id', metric = x ->> 'metric', target = public.mission_target(x -> 'target', ref, n_animals), progress = 0
    where user_id = v_user and kind = 'daily' and period = d and slot = p_slot;
  update public.farms set reroll_day = d where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;

-- o jogador viu as cartas novas virarem
create or replace function public.cards_seen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  update public.cards set seen = true where user_id = v_user and not seen;
  return public.farm_state(v_user);
end;
$$;

-- o que a tela mostra: missões de hoje e da semana, pacotes, cartas, buffs, Armory e garantia
create or replace function public.cards_state(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with f as (select * from public.farms where user_id = p_user), d as (select public.user_day(p_user, now()) d)
  select jsonb_build_object(
    'missions', (select coalesce(jsonb_agg(jsonb_build_object('kind', m.kind, 'slot', m.slot, 'id', m.mission_id, 'metric', m.metric,
        'target', m.target, 'progress', m.progress, 'done', m.done_at is not null, 'reward', m.reward) order by m.kind, m.slot), '[]')
      from public.missions m, d where m.user_id = p_user and ((m.kind = 'daily' and m.period = d.d) or (m.kind = 'weekly' and m.period = public.mission_week(d.d)))),
    'mission_week', (select jsonb_build_object('daily_packs', coalesce(w.daily_packs, 0), 'weekly_rewards', coalesce(w.weekly_rewards, 0))
      from d left join public.mission_weeks w on w.user_id = p_user and w.week = public.mission_week(d.d)),
    'reroll_used', (select f.reroll_day is not distinct from d.d from f, d),
    'pack_today', (select f.daily_pack_day is not distinct from d.d from f, d),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'state', c.state,
        'inbox_until', c.inbox_until, 'seen', c.seen, 'origin', c.origin) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and c.state in ('binder', 'inbox')),
    'new_cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'origin', c.origin) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and not c.seen),
    'buffs', (select coalesce(jsonb_agg(jsonb_build_object('card_id', b.card_id, 'rarity', b.rarity, 'started_at', b.started_at, 'ends_at', b.ends_at,
        'coin_value', b.coin_value) order by b.started_at), '[]') from public.card_buffs b where b.user_id = p_user and b.ends_at > now()),
    'armory', (select coalesce(jsonb_agg(jsonb_build_object('card_id', a.card_id, 'rarity', a.rarity)), '[]') from public.armory a where a.user_id = p_user),
    'pity', (select jsonb_build_object('rare', f.pity_rare, 'legendary', f.pity_legendary, 'mythic', f.pity_mythic) from f),
    'binder_slots', (select f.binder_slots from f),
    'prod_ref', public.prod_ref(p_user),
    'collector', (select jsonb_object_agg(r, public.collector_price(p_user, r)) from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) r),
    'binder_expand_cost', (select round(public.ref_income(f.level) * (public.config_get('cards') -> 'binder' ->> 'expansion_cost_reference_income_ratio')::numeric, 2) from f))
$$;

-- ---------- painel ----------
create or replace function public.admin_grant_card(p_user uuid, p_card text, p_rarity text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); v_serial bigint;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if public.card_def(p_card) is null or public.rarity_rank(p_rarity) is null then raise exception 'carta inválida' using errcode = 'check_violation'; end if;
  insert into public.cards (user_id, card_id, rarity, origin) values (p_user, p_card, p_rarity, 'admin') returning serial into v_serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_card', p_user, jsonb_build_object('serial', v_serial, 'card', p_card, 'rarity', p_rarity, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- completa as missões do jogador (para testar pacotes e prêmios); fica registrado
create or replace function public.admin_complete_missions(p_user uuid, p_kind text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); m record; d date;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if p_kind not in ('daily', 'weekly') then raise exception 'tipo inválido' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  perform public.mission_ensure(p_user, now());
  d := public.user_day(p_user, now());
  for m in select metric, max(target) t from public.missions
           where user_id = p_user and kind = p_kind and done_at is null and period = case when p_kind = 'daily' then d else public.mission_week(d) end
           group by metric loop
    perform public.mission_progress(p_user, m.metric, m.t);
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.complete_missions', p_user, jsonb_build_object('kind', p_kind, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.jnum(jsonb, text)', 'public.card_def(text)', 'public.rarity_rank(text)', 'public.card_fx(uuid, timestamptz)', 'public.draw_card(uuid, text)',
    'public.collector_price(uuid, text)', 'public.cards_maintain(uuid)', 'public.buffs_expire(uuid, timestamptz)', 'public.prod_roll(uuid, date)',
    'public.prod_ref(uuid)', 'public.nice_round(numeric)', 'public.mission_week(date)', 'public.mission_ensure(uuid, timestamptz)',
    'public.mission_target(jsonb, jsonb, int)', 'public.mission_progress(uuid, text, numeric)', 'public.produced(uuid, text, numeric, numeric, text)',
    'public.cards_state(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array['public.use_card(bigint)', 'public.armory_place(bigint)', 'public.sell_card(bigint)', 'public.binder_expand()',
    'public.reroll_mission(int)', 'public.cards_seen()', 'public.admin_grant_card(uuid, text, text, text)', 'public.admin_complete_missions(uuid, text, text)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;

-- ---------- funções que mudam na fase 7 ----------
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
    'sales_gold', least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100, (s ->> 'sales_gold_pct')::double precision / 100 + papagaio + public.jnum(ca, 'sales_gold_pct') / 100),
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
    'exp_success', (s ->> 'expedition_success_pts')::double precision + dog_pts + public.jnum(ca, 'expedition_success_pts') + public.jnum(cb, 'expedition_success_pts'),
    'exp_duration', (s ->> 'expedition_duration_pct')::double precision / 100,
    'vehicle_wear', (s ->> 'vehicle_wear_pct')::double precision / 100,
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
    'w_speed_cleanup', public.jnum(cb, 'all_speed_pct') / 100,
    'coin', public.jnum(cb, 'production_gold_bonus_pct') / 100,
    -- Fôlego: gasto de energia em campo e recuperação no banco
    'card_use_cut', least(1, public.jnum(cb, 'energy_cost_reduction_pct') / 100),
    'card_rest_perm', public.jnum(ca, 'energy_recovery_boost_pct') / 100,
    'card_rest_buff', public.jnum(cb, 'energy_recovery_boost_pct') / 100,
    -- Estrada Livre e Trevo: ficam gravados na expedição que parte agora
    'exp_card', jsonb_build_object('loss_red', public.jnum(cb, 'expedition_loss_reduction_pct'),
        'crit_pts', public.jnum(cb, 'expedition_crit_pts') + public.jnum(ca, 'expedition_crit_pts'),
        'crit_val', public.jnum(cb, 'expedition_crit_value_pct'),
        'item_boost', public.jnum(cb, 'item_and_kit_drop_boost_pct') + public.jnum(ca, 'item_drop_boost_pct')),
    'cards', cf);
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
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + public.item_effect(c, 'max_energy_bonus'),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'absolute')::double precision, 100) / 100,
             (1 - coalesce((fx ->> 'card_use_cut')::double precision, 0)) * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + public.skill_effect(c.class_id, c.skills, 'energy_use_pct') / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * (1 - public.item_effect(c, 'energy_cost_reduction_pct') / 100)
                           * case when fx -> 'pet' ->> 'linked' = c.class_id then 1 - (ch -> 'pets' ->> 'per_level_energy_use_pct')::double precision * (fx -> 'pet' ->> 'level')::int / 100 else 1 end)),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'absolute')::double precision, 200) / 100,
             coalesce((fx ->> 'card_rest_buff')::double precision, 0) + least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') / 100) * (1 + coalesce((fx ->> 'card_rest_perm')::double precision, 0)))))
  from cfg
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
         + case when (d ->> 'is_bird')::boolean and public.lake_ready(p_user, p_t) then (r -> 'lake_bonus' ->> 'bird_production')::double precision else 0 end;
  m := public.rarity_mult(a.rarity) * (1 + least(bonus, coalesce((fx ->> 'animal_cap')::double precision, 0.6)))
     * case when p_team then case when coalesce((fx ->> 'rancheira')::boolean, false) then (r -> 'collector_efficiency' ->> 'rancheira')::double precision
                                  else (r -> 'collector_efficiency' ->> 'other_class')::double precision end else 1 end;
  if public.rand01() < coalesce((fx ->> 'animal_double')::double precision, 0) then m := m * 2; end if;
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
        ready_at = p_t + (c ->> 'grow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision),
        free_since = null, stalled_reason = null, rarity = p_rarity, seed_paid = v_seed
    where user_id = p_user and plot_id = p_plot;
  -- missão "plante um cultivo dos seus últimos níveis"
  if (c ->> 'unlock_level')::int >= (select level from public.farms where user_id = p_user) - (public.config_get('missions') ->> 'plant_top_window_levels')::int then
    perform public.mission_progress(p_user, 'plant_top', 1);
  end if;
  return v_seed;
end;
$function$;

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

create or replace function public.exp_resolve(p_id uuid, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; e jsonb := public.config_get('expeditions'); r jsonb; lead jsonb; u double precision; pc double precision;
  v_out text; v_gold numeric := 0; v_refund numeric := 0; v_loss double precision; v_back jsonb := '{}'; v_drops jsonb := '[]';
  v_rolls int := 1; k int; c record; v_lost int; v_rec boolean := false; v_txt text; v_items jsonb;
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
    v_rolls := (e -> 'crit' ->> 'item_rolls')::int;
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

  if v_gold > 0 then v_gold := v_gold + public.moon_bonus(x.user_id, v_gold, fx); end if;
  -- missões: ouro ganho e viagem longe com sucesso
  perform public.mission_progress(x.user_id, 'gold_earned', v_gold);
  if v_out <> 'fail' and public.exp_route_idx(x.route_id) >= public.exp_route_idx(public.config_get('missions') ->> 'far_route') then
    perform public.mission_progress(x.user_id, 'exp_far_success', 1);
  end if;

  -- prêmios: item (vestimenta ou amuleto), Escritura e Kit de Reforma
  v_items := (public.config_get('tools_and_items') -> 'clothing_cards') || (public.config_get('tools_and_items') -> 'amulet_cards');
  for k in 1 .. v_rolls loop
    if public.rand01() < (r ->> 'item_chance')::double precision * (1 + coalesce((lead ->> 'item_pct')::double precision, 0) / 100) * (1 + public.jnum(x.card_fx, 'item_boost') / 100) then
      v_drops := v_drops || to_jsonb((v_items -> floor(public.rand01() * jsonb_array_length(v_items))::int ->> 'id') || ':' || public.pick_rarity(r -> 'item_rarity'));
    end if;
  end loop;
  if public.rand01() < (r ->> 'deed_chance')::double precision * (1 + coalesce((lead ->> 'deed_pct')::double precision, 0) / 100) then
    v_drops := v_drops || to_jsonb('deed'::text);
  end if;
  if public.rand01() < (r ->> 'kit_chance')::double precision * (1 + public.jnum(x.card_fx, 'item_boost') / 100) then
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
$function$;

create or replace function public.sell_at_stall(p_item text, p_qty integer, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid(); v_moon numeric := 0;
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
  v_moon := public.moon_bonus(v_user, v_amount, fx);
  v_amount := v_amount + v_moon;
  perform public.ledger_post(v_user, v_amount, 'stall_sale', jsonb_build_object('item', p_item, 'qty', p_qty, 'price', v_price,
    'ratio', fx -> 'stall_ratio', 'sales_gold', fx -> 'sales_gold', 'boost', v_boost, 'moon', v_moon), p_idempotency_key);
  perform public.mission_progress(v_user, 'stall_gold', v_amount);
  perform public.mission_progress(v_user, 'gold_earned', v_amount);
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots set stalled_reason = null, free_since = v_time where user_id = v_user and stalled_reason = 'sem_ouro';
  perform public.advance_farm(v_user, now());
  perform public.feed_hungry_now(v_user);
  return public.farm_state(v_user);
end;
$function$;

create or replace function public.auto_sell(p_user uuid, fx jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_total numeric := 0; v_moon numeric := 0; v_items jsonb := '{}'::jsonb; v_price numeric;
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
    v_moon := public.moon_bonus(p_user, v_total, fx);
    v_total := v_total + v_moon;
    perform public.ledger_post(p_user, v_total, 'auto_sale', jsonb_build_object('items', v_items, 'ratio', fx -> 'stall_ratio', 'moon', v_moon));
    perform public.mission_progress(p_user, 'stall_gold', v_total);
    perform public.mission_progress(p_user, 'gold_earned', v_total);
  end if;
  return v_total;
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
      v_h := v_h + worked * (1 + public.item_effect(c, 'character_xp_pct') / 100 + coalesce((fx ->> 'char_xp')::double precision, 0)); -- Relógio de Bolso + neblina
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
    if v_lvl > c.level then perform public.mission_progress(p_user, 'char_level', v_lvl - c.level); end if;
    update public.characters set energy = v_e, work_hours = v_h, level = v_lvl, parked = v_park, snack_qty = v_qty,
        snack_id = case when v_qty = 0 then null else snack_id end, revive_day = v_rev
      where user_id = p_user and class_id = c.class_id;
  end loop;
end;
$function$;

create or replace function public.repair_vehicle(p_vehicle text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  perform public.mission_progress(v_user, 'vehicle_repair', 1);
  return public.farm_state(v_user);
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
  e record; lt double precision; te double precision; v_real timestamptz; v_w jsonb; v_g double precision; v_cut double precision;
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

  while seg0 < t1 loop
    -- relógio real do passo: o clima e o evento valem pela hora local do jogador
    v_real := f.synced_at + make_interval(secs => seg0 - t0);
    perform set_config('vif.at', v_real::text, true);
    v_w := public.weather_now(p_user, v_real);
    v_cut := extract(epoch from ((v_w ->> 'next')::timestamptz - v_real));
    -- cartas: buffs que acabaram pagam a Moeda da Sorte; o passo também corta no fim do próximo buff
    perform public.buffs_expire(p_user, v_real);
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.card_buffs where user_id = p_user and ends_at > v_real));
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
    -- Sol forte e Calor Dourado: quem está crescendo anda mais rápido neste passo (lavoura e pomar)
    v_g := coalesce((fx ->> 'w_growth')::double precision, 0);
    if v_g > 0 then
      update public.plots set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                              else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and state = 'growing' and ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_growth_orchard')::double precision, 0);
    if v_g > 0 then
      update public.trees set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                              else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and fruit_id is not null and ready_at > seg0;
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
        'exp_success', fx -> 'exp_success', 'exp_duration', fx -> 'exp_duration', 'vehicle_wear', fx -> 'vehicle_wear', 'dog_recover', fx -> 'dog_recover',
        'char_xp', fx -> 'char_xp', 'account_xp', fx -> 'account_xp')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base || public.exp_state(p_user) || public.cards_state(p_user);
end;
$function$;
