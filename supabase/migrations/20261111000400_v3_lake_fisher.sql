-- Lago igual ao Galinheiro e ao Celeiro (pedido do dono em 04/11): vagas com peixe escolhido e raridade sorteada,
-- coleta pela fila da equipe; o Pescador (novo personagem, nível 30) é o especialista do Lago e a Vara de Pescar é a ferramenta dele.
-- A rede de pesca de 2 h e a Vara da fazenda saem.

-- Gerada por "npm run db:migration" a partir de supabase/functions/ (mudam: advance_farm, animal_collect, farm_state, item_price, team_fx; saem: collect_fish, fish_collect, fish_cycles, fish_species, fish_state, repair_rod, rod_repair_cost).

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
  perform public.tools_autotier(p_user);
  perform public.pets_unlock(p_user, t1);
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
end;
$function$;

create or replace function public.animal_collect(p_user uuid, p_house text, p_slot integer, p_t double precision, fx jsonb, p_team boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.animals; d jsonb; r jsonb := public.config_get('animals') -> 'rules'; m double precision; bonus double precision; v_qty int; v_fish boolean;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  d := public.animal_def(a.animal_id);
  v_fish := coalesce((d ->> 'is_fish')::boolean, false);
  -- peixe do Lago: bônus de pesca (carta Pesca) no lugar dos bônus de animais; ave: + nó Aves
  bonus := case when v_fish then coalesce((fx ->> 'fishing')::double precision, 0)
                else coalesce((fx ->> 'animal_production')::double precision, 0)
                   + case when (d ->> 'is_bird')::boolean then coalesce((fx ->> 'bird_bonus')::double precision, 0) else 0 end end;
  -- fora do jogo a equipe coleta a 100% com o especialista da casa em campo (Rancheira; Pescador no Lago), senão 60%
  m := public.rarity_mult(a.rarity) * (1 + least(bonus, coalesce((fx ->> 'animal_cap')::double precision, 0.6)))
     * case when p_team then case when coalesce((fx ->> (r -> 'collector_efficiency' -> 'specialist_by_house' ->> p_house))::boolean, false)
                                  then (r -> 'collector_efficiency' ->> 'specialist')::double precision
                                  else (r -> 'collector_efficiency' ->> 'other_class')::double precision end else 1 end;
  if v_fish then
    if public.rand01() < coalesce((fx ->> 'legendary_fish')::double precision, 0) then m := m * 2; end if;  -- Mestre Pescador
  elsif public.rand01() < coalesce((fx ->> 'animal_double')::double precision, 0) + coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- + Mutação Genética
  v_qty := public.round_rand(coalesce((r ->> 'units_per_collect')::double precision, 1) * m);
  if v_qty > 0 then
    insert into public.silo (user_id, item_id, qty) values (p_user, d -> 'product' ->> 'id', v_qty)
      on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
    perform public.produced(p_user, d -> 'product' ->> 'id', v_qty, (d ->> 'xp_per_collect')::numeric, case when v_fish then 'fish' else 'animal' end);
  end if;
  perform public.add_xp(p_user, round((d ->> 'xp_per_collect')::numeric * (1 + (fx ->> 'account_xp')::numeric), 2));
  update public.animals set ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_qty;
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
      'material', coalesce(t.material, 'wood'), 'durability', round(coalesce(t.durability, 100)::numeric, 2),
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
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira', 'pescador', fx -> 'pescador',
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

create or replace function public.item_price(p_item text)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce((public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric,
    (select (x -> 'product' ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('animals') -> 'animals') x
     where x -> 'product' ->> 'id' = p_item limit 1))
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
  ranch boolean := false; fisher boolean := false;
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0; gato_animal double precision := 0;
  cf jsonb := public.card_fx(p_user, public.fx_at()); cb jsonb; ca jsonb; v_storm double precision;
  v_res jsonb; v_w jsonb := public.weather_now(p_user, public.fx_at()); wcfg jsonb := public.config_get('weather');
  wm double precision; em double precision; cw jsonb; ew jsonb; v_base double precision; v_room double precision; v_cg double precision;
  v_go double precision; v_xp double precision; v_cxp double precision; v_sales double precision; v_warn int;
  dog_pts double precision := 0; dog_rec double precision := 0;
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
    if c.class_id = 'pescador' then fisher := true; end if;
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
  v_res := jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision + public.jnum(ca, 'crop_and_orchard_growth_speed_pct') + public.jnum(ca, 'crop_orchard_animal_speed_pct')) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100),
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
                         ((s ->> 'animal_production_pct')::double precision + public.jnum(ca, 'animal_production_pct')) / 100 + gato_animal)
                         + public.jnum(cb, 'animal_production_pct') / 100,
    'animal_cap', coalesce((caps -> 'animal_production_pct' ->> 'absolute')::double precision, 250) / 100,
    'animal_double', (s ->> 'animal_double_pct')::double precision / 100,
    'expansion_cost', (s ->> 'expansion_cost_pct')::double precision / 100,
    'rancheira', ranch,
    'pescador', fisher,
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

drop function if exists public.collect_fish();
drop function if exists public.fish_collect(p_user uuid, p_t double precision, fx jsonb, p_team boolean);
drop function if exists public.fish_cycles(p_user uuid, p_t double precision);
drop function if exists public.fish_species(p_level int);
drop function if exists public.fish_state(p_user uuid);
drop function if exists public.repair_rod();
drop function if exists public.rod_repair_cost(p_user uuid);


-- a rede e a Vara da fazenda não existem mais (a Vara agora é a ferramenta do Pescador, na tabela tools)
alter table public.farms drop column if exists fish_t;
alter table public.farms drop column if exists rod_durability;
