-- Reformulação v3, ajuste da R2: a mão só GUARDA as cartas; a carta vale e gasta o tempo só depois de "Usar"
-- (pedido do dono em 01/11). Vagas da mão (3 a 5) = cartas guardadas + cartas em uso.
-- hand_add: fichário → mão (parada). equip_card ("Usar"): da mão ou do fichário → em uso, conta o tempo.
-- unequip_card ("Pausar", depois de 1 dia): em uso → volta parada para a mão, guardando o tempo. hand_remove: mão → fichário.
alter table public.cards drop constraint cards_state_check;
alter table public.cards add constraint cards_state_check check (state in ('binder', 'inbox', 'armory', 'used', 'sold', 'equipped', 'worn', 'hand'));

-- cartas ocupando a mão (paradas + em uso)
create or replace function public.hand_count(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select count(*)::int from public.cards where user_id = p_user and state in ('hand', 'equipped')
$$;

-- fichário → mão (parada, sem gastar tempo)
create or replace function public.hand_add(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if coalesce(c.life_seconds, public.card_full_life(c.rarity)) <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.cards where user_id = v_user and card_id = c.card_id and state in ('hand', 'equipped')) then
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

-- mão → fichário (só carta parada)
create or replace function public.hand_remove(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state = 'hand' for update;
  if not found then raise exception 'essa carta não está parada na mão' using errcode = 'check_violation'; end if;
  if (select count(*) from public.cards where user_id = v_user and state in ('binder', 'worn')) >= (select binder_slots from public.farms where user_id = v_user) then
    raise exception 'o fichário está cheio' using errcode = 'check_violation';
  end if;
  update public.cards set state = 'binder', changed_at = now() where serial = c.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.from_hand', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id));
  return public.farm_state(v_user);
end;
$$;


create or replace function public.equip_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; cfg jsonb := public.config_get('cards'); v_life double precision; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'hand') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v_life := coalesce(c.life_seconds, public.card_full_life(c.rarity));
  if v_life <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.card_buffs where user_id = v_user and card_id = c.card_id) then
    raise exception 'essa carta já está na mão' using errcode = 'check_violation';
  end if;
  if c.state <> 'hand' and exists (select 1 from public.cards where user_id = v_user and card_id = c.card_id and state = 'hand') then
    raise exception 'essa carta já está na mão' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  -- vinda do fichário precisa de vaga; já na mão, só passa a valer
  if c.state <> 'hand' and public.hand_count(v_user) >= public.hand_slots(v_level) then
    raise exception 'a mão está cheia' using errcode = 'check_violation';
  end if;
  insert into public.card_buffs (user_id, card_id, rarity, serial, started_at, ends_at, locked_until)
    values (v_user, c.card_id, c.rarity, c.serial, now(), now() + make_interval(secs => v_life),
            now() + make_interval(hours => (cfg -> 'rules' -> 'hand' ->> 'min_lock_hours')::int));
  update public.cards set state = 'equipped', life_seconds = v_life, seen = true, inbox_until = null, changed_at = now() where serial = c.serial;
  insert into public.armory (user_id, card_id, rarity, serial) values (v_user, c.card_id, c.rarity, c.serial) on conflict do nothing;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.equipped', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'life_s', round(v_life::numeric)));
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;

create or replace function public.card_leave_hand(p_user uuid, b public.card_buffs, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_left double precision := greatest(0, extract(epoch from (b.ends_at - p_at)));
begin
  if b.coin_value > 0 then
    perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial || ':' || extract(epoch from p_at));
  end if;
  delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  update public.cards set life_seconds = v_left, changed_at = now(),
      state = case when v_left > 0 then 'hand' when rarity = 'common' then 'worn' else 'used' end
    where serial = b.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, case when v_left > 0 then 'card.unequipped' else 'card.worn_out' end, p_user, jsonb_build_object('serial', b.serial, 'card', b.card_id, 'rarity', b.rarity, 'left_s', round(v_left::numeric)));
  if b.card_id = 'veiculo' then perform public.vehicle_card_cleanup(p_user); end if;
end;
$$;

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
        'life_s', round(coalesce(c.life_seconds, public.card_full_life(c.rarity))::numeric), 'full_s', public.card_full_life(c.rarity), 'repairs', c.repairs) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and c.state in ('binder', 'inbox', 'worn', 'hand')),
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
