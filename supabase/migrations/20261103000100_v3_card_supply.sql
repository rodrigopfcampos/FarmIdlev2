-- Reformulação v3, ajuste da R2: de onde vêm as cartas (aprovado pelo dono em 01/11).
-- 3 Comuns na mão ao criar a conta; 1 carta por nível do 2 ao 10; as 5 diárias dão 1 pacote todo dia
-- (sem o limite de 4 por semana) e o pacote traz 2 cartas do nível 15 em diante. Números em config.
alter table public.farms add column starter_cards_at timestamptz;
alter table public.farms add column level_cards_to integer not null default 1;
-- contas que já existem não ganham cartas pelos níveis que já passaram
update public.farms set level_cards_to = level;

-- presente inicial: as cartas Comuns da config, direto na mão (soltas: dá para trocar na hora)
create or replace function public.cards_starter(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare s jsonb := public.config_get('cards') -> 'rules' -> 'supply'; f public.farms; k text; v_serial bigint; v_life double precision; v_r text;
begin
  -- testes antigos (fases 0–6) desligam as missões e as cartas de presente junto
  if current_setting('vif.missions', true) = 'off' then return; end if;
  select * into f from public.farms where user_id = p_user for update;
  if not found or f.starter_cards_at is not null then return; end if;
  update public.farms set starter_cards_at = now() where user_id = p_user;
  v_r := s ->> 'starter_rarity';
  v_life := public.card_full_life(v_r);
  for k in select jsonb_array_elements_text(s -> 'starter_cards') loop
    if coalesce((s ->> 'starter_to_hand')::boolean, false)
       and not exists (select 1 from public.card_buffs where user_id = p_user and card_id = k)
       and (select count(*) from public.card_buffs where user_id = p_user) < public.hand_slots(f.level) then
      insert into public.cards (user_id, card_id, rarity, state, origin, life_seconds, seen)
        values (p_user, k, v_r, 'equipped', 'starter', v_life, true) returning serial into v_serial;
      insert into public.card_buffs (user_id, card_id, rarity, serial, started_at, ends_at, locked_until)
        values (p_user, k, v_r, v_serial, now(), now() + make_interval(secs => v_life), now());
      insert into public.armory (user_id, card_id, rarity, serial) values (p_user, k, v_r, v_serial) on conflict do nothing;
    else
      insert into public.cards (user_id, card_id, rarity, state, origin) values (p_user, k, v_r, 'binder', 'starter') returning serial into v_serial;
    end if;
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'card.starter', p_user, jsonb_build_object('serial', v_serial, 'card', k, 'rarity', v_r));
  end loop;
end;
$$;

-- cartas por nível (do 2 ao 10 na config): cada nível só paga uma vez
create or replace function public.cards_level_up(p_user uuid, p_level int)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare l jsonb := public.config_get('cards') -> 'rules' -> 'supply' -> 'level_up_cards'; v_to int; lv int; k int;
begin
  if current_setting('vif.missions', true) = 'off' or l is null then return; end if;
  select level_cards_to into v_to from public.farms where user_id = p_user for update;
  for lv in greatest(v_to + 1, (l ->> 'from_level')::int) .. least(p_level, (l ->> 'to_level')::int) loop
    for k in 1 .. (l ->> 'cards_per_level')::int loop perform public.draw_card(p_user, 'level_up'); end loop;
  end loop;
  update public.farms set level_cards_to = greatest(level_cards_to, p_level) where user_id = p_user;
end;
$$;

-- cartas por pacote das diárias, pelo nível
create or replace function public.daily_pack_cards(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select coalesce(max((x ->> 1)::int), 1) from jsonb_array_elements(public.config_get('missions') -> 'daily' -> 'pack_cards_by_level') x
  where (x ->> 0)::int <= (select level from public.farms where user_id = p_user)
$$;


create or replace function public.add_xp(p_user uuid, p_xp numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_levels jsonb := public.config_get('levels') -> 'levels';
  v_level int; v_xp numeric; v_need numeric; v_start int; v_per numeric; v_stars int := 0;
begin
  select level, xp into v_level, v_xp from public.farms where user_id = p_user for update;
  v_start := v_level;
  v_xp := v_xp + p_xp;
  loop
    exit when v_level >= 50;
    v_need := (v_levels -> (v_level - 1) ->> 'xp_to_next')::numeric;
    exit when v_need is null or v_xp < v_need;
    v_xp := v_xp - v_need;
    v_level := v_level + 1;
  end loop;
  if v_level >= (public.config_get('village') -> 'stars' ->> 'unlock_level')::int then
    v_per := (v_levels -> 48 ->> 'xp_to_next')::numeric * (public.config_get('village') -> 'stars' ->> 'xp_per_star_ratio_of_level_49')::numeric;
    if v_per > 0 and v_xp >= v_per then
      v_stars := floor(v_xp / v_per)::int;
      v_xp := v_xp - v_stars * v_per;
    end if;
    v_xp := greatest(v_xp, 0);
  end if;
  update public.farms set level = v_level, xp = round(v_xp, 2), stars = stars + v_stars where user_id = p_user;
  if v_level > v_start then
    perform public.cards_level_up(p_user, v_level);
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'level.up', p_user, jsonb_build_object('from', v_start, 'to', v_level));
  end if;
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
        insert into public.inventory (user_id, item_id, qty) values (p_user, 'deed', (cfg -> 'weekly' ->> 'deed_at_5')::int)
          on conflict (user_id, item_id) do update set qty = public.inventory.qty + excluded.qty;
      end if;
    end if;
  end loop;
end;
$$;

create or replace function public.cards_maintain(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare c public.cards; v_free int; v numeric;
begin
  perform public.cards_starter(p_user);
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

create or replace function public.anticheat_check(p_user uuid, p_force boolean default false)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('anticheat'); r jsonb := c -> 'rules'; f public.farms; p public.profiles; n int := 0;
  v_age double precision; v_gain numeric; v_cards int; v_exp numeric; v_succ numeric; v_var numeric; v_cnt int; v_z numeric;
  v_sd double precision; v_acts int; v_ref int;
begin
  select * into f from public.farms where user_id = p_user;
  select * into p from public.profiles where id = p_user;
  if not found or f.user_id is null then return 0; end if;
  if not p_force and f.ac_checked_at is not null and f.ac_checked_at > now() - make_interval(mins => (c ->> 'check_every_minutes')::int) then return 0; end if;
  update public.farms set ac_checked_at = now() where user_id = p_user;
  v_age := extract(epoch from (now() - p.created_at)) / 86400;

  -- renda impossível
  select coalesce(sum(amount), 0) into v_gain from public.ledger
    where user_id = p_user and amount > 0 and created_at > now() - interval '24 hours'
      and not (reason = any (array(select jsonb_array_elements_text(r -> 'income' -> 'ignore_reasons'))));
  if v_gain > public.ref_income(f.level) * (r -> 'income' ->> 'max_R_per_day')::numeric then
    if public.raise_alert(p_user, 'income', jsonb_build_object('gold_24h', v_gain, 'level', f.level, 'R', public.ref_income(f.level))) is not null then n := n + 1; end if;
  end if;

  -- progresso rápido demais
  if f.level >= (r -> 'progress' ->> 'min_level')::int
     and v_age < public.dedicated_day(f.level) * (1 - (r -> 'progress' ->> 'slack')::double precision) then
    if public.raise_alert(p_user, 'progress', jsonb_build_object('level', f.level, 'age_days', round(v_age::numeric, 2),
         'dedicated_day', round(public.dedicated_day(f.level)::numeric, 2))) is not null then n := n + 1; end if;
  end if;

  -- cartas a mais
  select count(*) into v_cards from public.cards where user_id = p_user
    and origin <> all (array(select jsonb_array_elements_text(coalesce(r -> 'cards' -> 'ignore_origins', '["admin"]'))));
  if v_cards > greatest((r -> 'cards' ->> 'min_weeks')::numeric, ceil(v_age / 7)) * (r -> 'cards' ->> 'max_per_week')::numeric then
    if public.raise_alert(p_user, 'cards', jsonb_build_object('cards', v_cards, 'weeks', ceil(v_age / 7))) is not null then n := n + 1; end if;
  end if;

  -- sorte impossível nas expedições (sucessos acima do esperado)
  select count(*), coalesce(sum(case when outcome <> 'fail' then 1 else 0 end), 0), coalesce(sum(chance), 0), coalesce(sum(chance * (1 - chance)), 0)
    into v_cnt, v_succ, v_exp, v_var
    from (select outcome, chance from public.expeditions where user_id = p_user and status = 'back' order by returns_at desc limit (r -> 'luck' ->> 'last_n')::int) x;
  if v_cnt >= (r -> 'luck' ->> 'min_n')::int and v_var > 0 then
    v_z := (v_succ - v_exp) / sqrt(v_var);
    if v_z > (r -> 'luck' ->> 'z')::numeric then
      if public.raise_alert(p_user, 'luck', jsonb_build_object('trips', v_cnt, 'successes', v_succ, 'expected', round(v_exp, 2), 'z', round(v_z, 2))) is not null then n := n + 1; end if;
    end if;
  end if;

  -- robô: intervalos quase iguais entre as ações
  select count(*), stddev_samp(dt) into v_acts, v_sd from (
    select extract(epoch from (at - lag(at) over (order by at))) * 1000 dt from public.action_times
    where user_id = p_user and at > now() - make_interval(mins => (r -> 'robot' ->> 'window_minutes')::int)) x where dt is not null;
  if v_acts >= (r -> 'robot' ->> 'min_actions')::int and v_sd < (r -> 'robot' ->> 'max_stddev_ms')::double precision then
    if public.raise_alert(p_user, 'robot', jsonb_build_object('actions', v_acts, 'stddev_ms', round(v_sd::numeric, 1))) is not null then n := n + 1; end if;
  end if;
  delete from public.action_times where user_id = p_user and at < now() - interval '6 hours';

  -- tentativa de manipular: muitas recusas em 1 hora
  select count(*) into v_ref from public.refusals where user_id = p_user and at > now() - interval '1 hour';
  if v_ref > (r -> 'refusals' ->> 'per_hour')::int then
    if public.raise_alert(p_user, 'refusals', jsonb_build_object('refusals_1h', v_ref,
         'last', (select jsonb_agg(jsonb_build_object('fn', fn, 'msg', msg)) from (select fn, msg from public.refusals where user_id = p_user order by at desc limit 5) z))) is not null then n := n + 1; end if;
  end if;

  -- minigame de robô (o minigame já registra no audit_log)
  if exists (select 1 from public.audit_log where actor_id = p_user and action = 'cheat.minigame_robot' and created_at > now() - interval '24 hours') then
    if public.raise_alert(p_user, 'minigame_robot', jsonb_build_object('count_24h',
         (select count(*) from public.audit_log where actor_id = p_user and action = 'cheat.minigame_robot' and created_at > now() - interval '24 hours'))) is not null then n := n + 1; end if;
  end if;

  -- fuso da conta diferente do aparelho por 7 dias
  if p.tz_mismatch_since is not null and p.tz_mismatch_since < now() - make_interval(days => (r -> 'timezone' ->> 'days')::int) then
    if public.raise_alert(p_user, 'timezone', jsonb_build_object('since', p.tz_mismatch_since, 'account_tz', p.timezone)) is not null then n := n + 1; end if;
  end if;
  return n;
end;
$$;
