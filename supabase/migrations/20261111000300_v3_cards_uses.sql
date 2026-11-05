-- Cartas por uso (pedido do dono em 04/11): a carta vale pelas próximas 1 a 5 coletas (Comum 1 … Mítica 5) em vez de dias,
-- gasta só na atividade que melhora, e qualquer coleta pode trazer carta nova (até 4 por dia).
alter table public.cards add column if not exists uses_left numeric;          -- usos que sobram (nulo = inteira)
alter table public.card_buffs add column if not exists uses_left numeric;     -- usos que faltam na carta em uso
alter table public.farms add column if not exists collect_cards_day date;     -- dia (do jogador) das cartas de coleta
alter table public.farms add column if not exists collect_cards_n integer not null default 0;

-- Gerada por "npm run db:migration" a partir de supabase/functions/ (mudam: advance_farm, card_full_uses, card_leave_hand, card_use, cards_starter, cards_state, equip_card, exp_depart, hand_add, harvest_tree, produced, repair_card; saem: card_full_life).

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
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.card_buffs where user_id = p_user and ends_at > v_real and ends_at < 'infinity'));
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

create or replace function public.card_full_uses(p_rarity text)
returns numeric language sql stable set search_path = '' as $$
  -- usos de uma carta inteira pela raridade (Comum 1 … Mítica 5)
  select (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'uses')::numeric
$$;

create or replace function public.card_leave_hand(p_user uuid, b public.card_buffs, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_left numeric := greatest(0, b.uses_left);
  v_room boolean := public.hand_count(p_user) < public.hand_slots((select level from public.farms where user_id = p_user))
    and not exists (select 1 from public.cards where user_id = p_user and card_id = b.card_id and state = 'hand');
begin
  if b.coin_value > 0 then
    perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial || ':' || extract(epoch from p_at));
  end if;
  delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  update public.cards set uses_left = v_left, changed_at = now(),
      state = case when v_left > 0 and v_room then 'hand' when v_left > 0 then 'binder' when rarity = 'common' then 'worn' else 'used' end
    where serial = b.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, case when v_left > 0 then 'card.unequipped' else 'card.worn_out' end, p_user, jsonb_build_object('serial', b.serial, 'card', b.card_id, 'rarity', b.rarity, 'uses_left', v_left));
  if b.card_id = 'veiculo' then perform public.vehicle_card_cleanup(p_user); end if;
end;
$$;

create or replace function public.card_use(p_user uuid, p_kind text, p_units numeric)
returns void language plpgsql volatile security definer set search_path = '' as $$
-- uma coleta (ou partida de expedição) gasta usos das cartas em uso que melhoram essa atividade ("any" = qualquer coleta);
-- a carta que zera sai da mão no fim do passo (buffs_expire) e a coleta pode trazer uma carta nova (até o limite do dia)
declare at timestamptz := public.fx_at(); cfg jsonb := public.config_get('cards') -> 'rules'; d jsonb; v_day date; f public.farms; k int;
begin
  if coalesce(p_units, 0) <= 0 then return; end if;
  update public.card_buffs set uses_left = greatest(0, uses_left - p_units),
      ends_at = case when uses_left - p_units <= 0 then at else ends_at end
    where user_id = p_user and started_at <= at and ends_at > at
      and (public.card_def(card_id) -> 'uses_on') ?| array[p_kind, 'any'];
  -- carta nova da coleta (a expedição tem o achado dela)
  if p_kind = 'expedition' or current_setting('vif.missions', true) = 'off' then return; end if;
  d := cfg -> 'collect_drop';
  v_day := public.user_day(p_user, at);
  select * into f from public.farms where user_id = p_user for update;
  if f.collect_cards_day is distinct from v_day then
    update public.farms set collect_cards_day = v_day, collect_cards_n = 0 where user_id = p_user;
    f.collect_cards_n := 0;
  end if;
  if f.collect_cards_n >= (d ->> 'max_per_day')::int then return; end if;
  if public.rand01() < least(1, (d ->> 'chance_per_use')::double precision * p_units) then
    perform public.draw_card(p_user, 'collect');
    update public.farms set collect_cards_n = collect_cards_n + 1 where user_id = p_user;
  end if;
end;
$$;

create or replace function public.cards_starter(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare s jsonb := public.config_get('cards') -> 'rules' -> 'supply'; f public.farms; k text; v_serial bigint; v_r text;
begin
  -- testes antigos (fases 0–6) desligam as missões e as cartas de presente junto
  if current_setting('vif.missions', true) = 'off' then return; end if;
  select * into f from public.farms where user_id = p_user for update;
  if not found or f.starter_cards_at is not null then return; end if;
  update public.farms set starter_cards_at = now() where user_id = p_user;
  v_r := s ->> 'starter_rarity';
  for k in select jsonb_array_elements_text(s -> 'starter_cards') loop
    -- na mão, parada: o jogador escolhe quando usar
    if coalesce((s ->> 'starter_to_hand')::boolean, false)
       and not exists (select 1 from public.cards where user_id = p_user and card_id = k and state in ('hand', 'equipped'))
       and public.hand_count(p_user) < public.hand_slots(f.level) then
      insert into public.cards (user_id, card_id, rarity, state, origin, seen)
        values (p_user, k, v_r, 'hand', 'starter', true) returning serial into v_serial;
    else
      insert into public.cards (user_id, card_id, rarity, state, origin) values (p_user, k, v_r, 'binder', 'starter') returning serial into v_serial;
    end if;
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'card.starter', p_user, jsonb_build_object('serial', v_serial, 'card', k, 'rarity', v_r));
  end loop;
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
        'uses', coalesce(c.uses_left, public.card_full_uses(c.rarity)), 'full_uses', public.card_full_uses(c.rarity), 'repairs', c.repairs) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and c.state in ('binder', 'inbox', 'worn', 'hand')),
    'new_cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'origin', c.origin) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and not c.seen),
    'buffs', (select coalesce(jsonb_agg(jsonb_build_object('card_id', b.card_id, 'rarity', b.rarity, 'serial', b.serial, 'started_at', b.started_at, 'ends_at', b.ends_at,
        'locked_until', b.locked_until, 'coin_value', b.coin_value, 'uses', b.uses_left, 'full_uses', public.card_full_uses(b.rarity)) order by b.started_at), '[]') from public.card_buffs b where b.user_id = p_user and b.ends_at > now()),
    'hand_slots', (select public.hand_slots(f.level) from f),
    'repair_cost', public.card_repair_cost(p_user),
    'armory', (select coalesce(jsonb_agg(jsonb_build_object('card_id', a.card_id, 'rarity', a.rarity)), '[]') from public.armory a where a.user_id = p_user),
    'pity', (select jsonb_build_object('rare', f.pity_rare, 'legendary', f.pity_legendary, 'mythic', f.pity_mythic) from f),
    'binder_slots', (select f.binder_slots from f),
    'prod_ref', public.prod_ref(p_user),
    'collector', (select jsonb_object_agg(r, public.collector_price(p_user, r)) from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) r),
    'binder_expand_cost', (select round(public.ref_income(f.level) * (public.config_get('cards') -> 'binder' ->> 'expansion_cost_reference_income_ratio')::numeric, 2) from f))
$$;

create or replace function public.equip_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; cfg jsonb := public.config_get('cards'); v_uses numeric; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'hand') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v_uses := coalesce(c.uses_left, public.card_full_uses(c.rarity));
  if v_uses <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.card_buffs where user_id = v_user and card_id = c.card_id) then
    raise exception 'essa carta já está em uso' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  -- buffs em uso: até as vagas do nível
  if (select count(*) from public.card_buffs where user_id = v_user) >= public.hand_slots(v_level) then
    raise exception 'limite de cartas em uso' using errcode = 'check_violation';
  end if;
  -- vale pelos próximos usos: sem prazo ("ends_at" vira a hora do último uso)
  insert into public.card_buffs (user_id, card_id, rarity, serial, started_at, ends_at, locked_until, uses_left)
    values (v_user, c.card_id, c.rarity, c.serial, now(), 'infinity',
            now() + make_interval(hours => (cfg -> 'rules' -> 'hand' ->> 'min_lock_hours')::int), v_uses);
  update public.cards set state = 'equipped', uses_left = v_uses, seen = true, inbox_until = null, changed_at = now() where serial = c.serial;
  insert into public.armory (user_id, card_id, rarity, serial) values (v_user, c.card_id, c.rarity, c.serial) on conflict do nothing;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.equipped', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'uses', v_uses));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

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
  perform public.card_use(p_user, 'expedition', (public.config_get('cards') -> 'rules' -> 'uses' -> 'units' ->> 'expedition')::numeric);
  update public.vehicles set durability = greatest(0, durability - (e ->> 'wear_per_trip_pct')::double precision * (1 + coalesce((fx ->> 'vehicle_wear')::double precision, 0)))
    where user_id = p_user and vehicle_id = v.vehicle_id;
  if v_ins > 0 then
    perform public.ledger_post(p_user, -v_ins, 'exp_insurance', jsonb_build_object('convoy', p_convoy, 'vehicle', v.vehicle_id, 'route', p_route, 'seq', p_seq));
  end if;
  return v_ins;
end;
$function$;

create or replace function public.hand_add(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if coalesce(c.uses_left, public.card_full_uses(c.rarity)) <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.cards where user_id = v_user and card_id = c.card_id and state = 'hand') then
    raise exception 'essa carta já está na mão' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  if public.hand_count(v_user) >= public.hand_slots(v_level) then raise exception 'a mão está cheia' using errcode = 'check_violation'; end if;
  update public.cards set state = 'hand', inbox_until = null, seen = true, changed_at = now() where serial = c.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.to_hand', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

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
  perform public.produced(p_user, tr.fruit_id, v_qty, (c ->> 'xp_per_harvest')::numeric * rm::numeric, 'orchard');
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, tr.fruit_id, fx);
  update public.trees set ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_orchard')::double precision),
      rare_left = greatest(0, rare_left - 1), rarity = case when rare_left <= 1 then null else rarity end
    where user_id = p_user and lot_id = p_lot and slot = p_slot;
end;
$function$;

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
  -- cartas por uso: 1 uso = um lote, pomar, casa de animais ou lago inteiro (config cards.rules.uses.units)
  perform public.card_use(p_user, p_kind, (public.config_get('cards') -> 'rules' -> 'uses' -> 'units' ->> p_kind)::numeric);
  perform public.mission_progress(p_user, 'xp_earned', p_xp);
  if p_kind = 'animal' then perform public.mission_progress(p_user, 'animal_products', p_qty);
  else perform public.mission_progress(p_user, 'harvest_value', v); end if;
end;
$$;

create or replace function public.repair_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; r jsonb := public.config_get('cards') -> 'rarities' -> 'common'; v_cost numeric; v_full numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'worn') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if c.rarity <> 'common' then raise exception 'só a carta Comum tem reparo' using errcode = 'check_violation'; end if;
  v_full := public.card_full_uses('common');
  if coalesce(c.uses_left, v_full) >= v_full then raise exception 'a carta está inteira' using errcode = 'check_violation'; end if;
  v_cost := public.card_repair_cost(v_user);
  perform public.ledger_post(v_user, -v_cost, 'card_repair', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'uses_left', coalesce(c.uses_left, 0)));
  update public.cards set uses_left = least(v_full, coalesce(uses_left, 0) + (r -> 'repair' ->> 'restores_uses')::numeric),
      repairs = repairs + 1, state = case when state = 'worn' then 'binder' else state end, changed_at = now()
    where serial = c.serial;
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

drop function if exists public.card_full_life(p_rarity text);


-- cartas que já estavam em uso ou guardadas com tempo gasto: voltam inteiras, agora por usos, sem prazo e sem trava
update public.card_buffs set uses_left = public.card_full_uses(rarity), ends_at = 'infinity', locked_until = null where uses_left is null;
update public.cards set uses_left = null, life_seconds = null where state in ('binder', 'inbox', 'hand', 'equipped');
update public.cards set uses_left = 0 where state = 'worn';
