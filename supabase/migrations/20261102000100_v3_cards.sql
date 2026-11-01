-- Reformulação v3, parte R2: as 20 cartas novas (config/cards.json v4).
-- A carta na mão vale por dias (online ou offline), fica presa pelo menos 1 dia e, ao sair, guarda o que sobrou.
-- Comum gasta vira "gasta" e o jogador repara com ouro; as outras somem. O álbum (Armory) registra sozinho na
-- primeira vez que a carta entra na mão. Mão de 3 a 5 cartas pelo nível. A Garagem não vende mais: cada veículo
-- libera de graça no nível dele; a carta de Veículo dá bônus às expedições e troca a aparência.

-- ---------- tabelas ----------
alter table public.cards add column life_seconds double precision;   -- vida que sobra (nulo = cheia)
alter table public.cards add column repairs integer not null default 0;
alter table public.cards drop constraint cards_state_check;
alter table public.cards add constraint cards_state_check check (state in ('binder', 'inbox', 'armory', 'used', 'sold', 'equipped', 'worn'));
alter table public.card_buffs add column locked_until timestamptz;
alter table public.vehicles add column from_card bigint;            -- veículo trazido pela carta de Veículo (nº de série)

-- ---------- regras das cartas ----------
create or replace function public.card_full_life(p_rarity text)
returns double precision language sql stable set search_path = '' as $$
  select (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'duration_days')::double precision * 86400
$$;

-- quantas cartas cabem na mão no nível
create or replace function public.hand_slots(p_level int)
returns int language sql stable set search_path = '' as $$
  select coalesce(max((x ->> 1)::int), 0) from jsonb_array_elements(public.config_get('cards') -> 'rules' -> 'hand' -> 'slots_by_level') x
  where (x ->> 0)::int <= p_level
$$;

-- preço do reparo da Comum: fração da renda do nível
create or replace function public.card_repair_cost(p_user uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(public.ref_income(f.level) * (public.config_get('cards') -> 'rarities' -> 'common' -> 'repair' ->> 'cost_reference_income_ratio')::numeric, 2)
  from public.farms f where f.user_id = p_user
$$;

-- a carta de Veículo saiu da mão: o veículo dela some (se estiver viajando, fica parado até voltar e ser recebido)
create or replace function public.vehicle_card_cleanup(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.vehicles v set active = false
    where v.user_id = p_user and v.from_card is not null
      and not exists (select 1 from public.card_buffs b where b.user_id = p_user and b.serial = v.from_card);
  delete from public.vehicles v
    where v.user_id = p_user and v.from_card is not null
      and not exists (select 1 from public.card_buffs b where b.user_id = p_user and b.serial = v.from_card)
      and not exists (select 1 from public.expeditions x where x.user_id = p_user and x.vehicle_id = v.vehicle_id and x.status in ('travel', 'back'));
  -- sem veículo ativo, a Carroça volta a ser o ativo
  if not exists (select 1 from public.vehicles where user_id = p_user and active) then
    update public.vehicles set active = true where user_id = p_user and vehicle_id = 'carroca';
  end if;
end;
$$;

-- tira a carta da mão: paga a Moeda e guarda a vida que sobrou (ou gasta: Comum vira "gasta", as outras somem)
create or replace function public.card_leave_hand(p_user uuid, b public.card_buffs, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_left double precision := greatest(0, extract(epoch from (b.ends_at - p_at)));
begin
  if b.coin_value > 0 then
    perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial || ':' || extract(epoch from p_at));
  end if;
  delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  update public.cards set life_seconds = v_left, changed_at = now(),
      state = case when v_left > 0 then 'binder' when rarity = 'common' then 'worn' else 'used' end
    where serial = b.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, case when v_left > 0 then 'card.unequipped' else 'card.worn_out' end, p_user, jsonb_build_object('serial', b.serial, 'card', b.card_id, 'rarity', b.rarity, 'left_s', round(v_left::numeric)));
  if b.card_id = 'veiculo' then perform public.vehicle_card_cleanup(p_user); end if;
end;
$$;

-- equipar: cabe na mão, sem repetir a carta, com vida; o álbum registra
create or replace function public.equip_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; cfg jsonb := public.config_get('cards'); v_life double precision; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v_life := coalesce(c.life_seconds, public.card_full_life(c.rarity));
  if v_life <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.card_buffs where user_id = v_user and card_id = c.card_id) then
    raise exception 'essa carta já está na mão' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  if (select count(*) from public.card_buffs where user_id = v_user) >= public.hand_slots(v_level) then
    raise exception 'a mão está cheia' using errcode = 'check_violation';
  end if;
  insert into public.card_buffs (user_id, card_id, rarity, serial, started_at, ends_at, locked_until)
    values (v_user, c.card_id, c.rarity, c.serial, now(), now() + make_interval(secs => v_life),
            now() + make_interval(hours => (cfg -> 'rules' -> 'hand' ->> 'min_lock_hours')::int));
  update public.cards set state = 'equipped', life_seconds = v_life, seen = true, changed_at = now() where serial = c.serial;
  insert into public.armory (user_id, card_id, rarity, serial) values (v_user, c.card_id, c.rarity, c.serial) on conflict do nothing;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.equipped', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'life_s', round(v_life::numeric)));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

-- o nome antigo continua (o jogo da fase 7 chamava "usar")
create or replace function public.use_card(p_serial bigint)
returns jsonb language sql security definer set search_path = '' as $$ select public.equip_card(p_serial) $$;

-- tirar da mão (depois da trava mínima)
create or replace function public.unequip_card(p_card text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); b public.card_buffs;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into b from public.card_buffs where user_id = v_user and card_id = p_card for update;
  if not found then raise exception 'essa carta não está na mão' using errcode = 'check_violation'; end if;
  if b.locked_until is not null and b.locked_until > now() then raise exception 'a carta ainda está presa na mão' using errcode = 'check_violation'; end if;
  perform public.card_leave_hand(v_user, b, now());
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

-- reparo: só a Comum; devolve dias (até a vida cheia) por ouro
create or replace function public.repair_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; r jsonb := public.config_get('cards') -> 'rarities' -> 'common'; v_cost numeric; v_full double precision;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'worn') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if c.rarity <> 'common' then raise exception 'só a carta Comum tem reparo' using errcode = 'check_violation'; end if;
  v_full := public.card_full_life('common');
  if coalesce(c.life_seconds, v_full) >= v_full then raise exception 'a carta está inteira' using errcode = 'check_violation'; end if;
  v_cost := public.card_repair_cost(v_user);
  perform public.ledger_post(v_user, -v_cost, 'card_repair', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'life_s', round(coalesce(c.life_seconds, 0)::numeric)));
  update public.cards set life_seconds = least(v_full, coalesce(life_seconds, 0) + (r -> 'repair' ->> 'restores_days')::double precision * 86400),
      repairs = repairs + 1, state = case when state = 'worn' then 'binder' else state end, changed_at = now()
    where serial = c.serial;
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

-- o álbum registra sozinho: colocar no Armory à mão não existe mais
create or replace function public.armory_place(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'o álbum registra a carta sozinho quando ela entra na mão' using errcode = 'check_violation';
end;
$$;

-- fim da vida na mão (no tempo da fazenda)
create or replace function public.buffs_expire(p_user uuid, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare b public.card_buffs;
begin
  for b in select * from public.card_buffs where user_id = p_user and ends_at <= p_at for update loop
    perform public.card_leave_hand(p_user, b, b.ends_at);
  end loop;
end;
$$;

-- cada veículo libera de graça no nível dele (a Garagem não vende)
create or replace function public.vehicles_unlock(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_level int;
begin
  select level into v_level from public.farms where user_id = p_user;
  insert into public.vehicles (user_id, vehicle_id, active)
    select p_user, x ->> 'id', false from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x
    where (x ->> 'unlock_level')::int <= coalesce(v_level, 1)
    on conflict do nothing;
end;
$$;

-- a Garagem não vende mais
create or replace function public.buy_vehicle(p_vehicle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'a Garagem não vende veículos: eles liberam sozinhos no nível de cada um' using errcode = 'check_violation';
end;
$$;

create or replace function public.sell_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'worn') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v := public.collector_price(v_user, c.rarity);
  update public.cards set state = 'sold', seen = true, changed_at = now() where serial = c.serial;
  perform public.ledger_post(v_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity), 'card:' || c.serial);
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;
create or replace function public.cards_maintain(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare c public.cards; v_free int; v numeric;
begin
  for c in select * from public.cards where user_id = p_user and state = 'inbox' and inbox_until <= now() order by serial for update loop
    v := public.collector_price(p_user, c.rarity);
    update public.cards set state = 'sold', changed_at = now() where serial = c.serial;
    if v > 0 then perform public.ledger_post(p_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'auto', true), 'card:' || c.serial); end if;
  end loop;
  select f.binder_slots - (select count(*) from public.cards where user_id = p_user and state in ('binder', 'worn')) into v_free from public.farms f where f.user_id = p_user;
  if v_free > 0 then
    update public.cards set state = 'binder', inbox_until = null, changed_at = now()
      where serial in (select serial from public.cards where user_id = p_user and state = 'inbox' order by serial limit v_free);
  end if;
  perform public.vehicle_card_cleanup(p_user);
end;
$$;
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
  if v.from_card is not null then raise exception 'o veículo da carta não pode ser reformado' using errcode = 'check_violation'; end if;
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
        'inbox_until', c.inbox_until, 'seen', c.seen, 'origin', c.origin,
        'life_s', round(coalesce(c.life_seconds, public.card_full_life(c.rarity))::numeric), 'full_s', public.card_full_life(c.rarity), 'repairs', c.repairs) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and c.state in ('binder', 'inbox', 'worn')),
    'new_cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'origin', c.origin) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and not c.seen),
    'buffs', (select coalesce(jsonb_agg(jsonb_build_object('card_id', b.card_id, 'rarity', b.rarity, 'serial', b.serial, 'started_at', b.started_at, 'ends_at', b.ends_at,
        'locked_until', b.locked_until, 'coin_value', b.coin_value, 'full_s', public.card_full_life(b.rarity)) order by b.started_at), '[]') from public.card_buffs b where b.user_id = p_user and b.ends_at > now()),
    'hand_slots', (select public.hand_slots(f.level) from f),
    'repair_cost', public.card_repair_cost(p_user),
    'armory', (select coalesce(jsonb_agg(jsonb_build_object('card_id', a.card_id, 'rarity', a.rarity)), '[]') from public.armory a where a.user_id = p_user),
    'pity', (select jsonb_build_object('rare', f.pity_rare, 'legendary', f.pity_legendary, 'mythic', f.pity_mythic) from f),
    'binder_slots', (select f.binder_slots from f),
    'prod_ref', public.prod_ref(p_user),
    'collector', (select jsonb_object_agg(r, public.collector_price(p_user, r)) from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) r),
    'binder_expand_cost', (select round(public.ref_income(f.level) * (public.config_get('cards') -> 'binder' ->> 'expansion_cost_reference_income_ratio')::numeric, 2) from f))
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
    'tool_wear_cut', least(0.9, (public.jnum(cb, 'cleanup_tool_vehicle_pct') + public.jnum(ca, 'cleanup_tool_vehicle_pct')) / 100),
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
    'cards', cf);
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
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
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
      update public.tools set durability = greatest(0, durability - (dr ->> 'loss_per_work_hour')::double precision * worked * (1 - coalesce((fx ->> 'tool_wear_cut')::double precision, 0)))
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

  if v_gold > 0 then v_gold := round(v_gold * (1 + public.jnum(x.card_fx, 'profit')::numeric / 100), 2); end if;  -- carta de Veículo
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
    if v.from_card is not null and not exists (select 1 from public.card_buffs where user_id = v_user and serial = v.from_card) then
      raise exception 'a carta desse veículo saiu da mão' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = v_vid and status in ('travel', 'back')) then
      raise exception 'veículo ocupado (viajando ou esperando Receber)' using errcode = 'check_violation';
    end if;
    if public.exp_route_idx(p_route) > public.exp_route_idx(public.vehicle_def(v_vid) ->> 'max_route') then
      raise exception 'esse veículo não vai até essa rota' using errcode = 'check_violation';
    end if;
    -- a carga enche os veículos na ordem escolhida
    v_cap := floor(public.exp_capacity(v, case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then lead end)
                   * (1 + public.jnum(fx -> 'exp_card', 'cargo') / 100))::int;  -- carta de Veículo
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
create or replace function public.process_expeditions(p_user uuid, p_t double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; v public.vehicles; fx jsonb; lead jsonb; v_cargo jsonb; v_cap int; v_left int; c record; v_take int;
  v_gold numeric; i int := 0;
begin
  perform public.demand_ensure(public.game_day(now()));
  perform public.demand_ensure(public.game_day(now()) + 1);
  update public.vehicles set rarity = refurb_rarity, refurb_rarity = null, refurb_until = null
    where user_id = p_user and refurb_until is not null and refurb_until <= p_t;
  if not exists (select 1 from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t) then return; end if;
  loop
    i := i + 1; exit when i > 200;
    select * into x from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t order by returns_at, id limit 1;
    exit when not found;
    -- o clima, a noite e a Lua Cheia valem pela hora real em que o veículo volta
    perform set_config('vif.at', (select (fa.synced_at + make_interval(secs => x.returns_at - fa.farm_time))::text from public.farms fa where fa.user_id = p_user), true);
    fx := public.team_fx(p_user);
    perform public.exp_resolve(x.id, fx);
    if x.repeat_left > 0 then
      -- repetição: mesmos produtos da viagem, até a capacidade, com o que houver no Silo
      select * into v from public.vehicles where user_id = p_user and vehicle_id = x.vehicle_id;
      lead := case when x.led then public.lead_info(p_user) else null end;
      v_cap := floor(public.exp_capacity(v, lead) * (1 + public.jnum(fx -> 'exp_card', 'cargo') / 100))::int; v_left := v_cap; v_cargo := '{}';
      -- veículo da carta: sem a carta na mão, não repete
      if v.vehicle_id is null or (v.from_card is not null and not exists (select 1 from public.card_buffs where user_id = p_user and serial = v.from_card)) then v_left := 0; end if;
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
  perform set_config('vif.at', '', true);
end;
$function$;

revoke all on function public.vehicles_unlock(uuid), public.card_full_life(text), public.hand_slots(int), public.card_repair_cost(uuid), public.vehicle_card_cleanup(uuid),
  public.card_leave_hand(uuid, public.card_buffs, timestamptz) from public, anon, authenticated;
grant execute on function public.equip_card(bigint), public.unequip_card(text), public.repair_card(bigint) to authenticated;
revoke all on function public.equip_card(bigint), public.unequip_card(text), public.repair_card(bigint) from anon;

