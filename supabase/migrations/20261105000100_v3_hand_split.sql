-- Reformulação v3, ajuste da R2 (vídeo do dono, 01/11): ao usar, a carta SAI da mão e vira buff (mostrado no canto
-- superior esquerdo). A mão guarda só cartas paradas; as vagas (3 a 5 pelo nível) valem para a mão e, à parte, para os buffs.
-- Pausar devolve à mão se houver vaga; senão, ao fichário (sempre guardando o tempo que sobrou).
create or replace function public.hand_count(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select count(*)::int from public.cards where user_id = p_user and state = 'hand'
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
    raise exception 'essa carta já está em uso' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  -- buffs em uso: até as vagas do nível
  if (select count(*) from public.card_buffs where user_id = v_user) >= public.hand_slots(v_level) then
    raise exception 'limite de cartas em uso' using errcode = 'check_violation';
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

create or replace function public.hand_add(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  if coalesce(c.life_seconds, public.card_full_life(c.rarity)) <= 0 then raise exception 'carta gasta' using errcode = 'check_violation'; end if;
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

create or replace function public.card_leave_hand(p_user uuid, b public.card_buffs, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_left double precision := greatest(0, extract(epoch from (b.ends_at - p_at)));
  v_room boolean := public.hand_count(p_user) < public.hand_slots((select level from public.farms where user_id = p_user))
    and not exists (select 1 from public.cards where user_id = p_user and card_id = b.card_id and state = 'hand');
begin
  if b.coin_value > 0 then
    perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial || ':' || extract(epoch from p_at));
  end if;
  delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  update public.cards set life_seconds = v_left, changed_at = now(),
      state = case when v_left > 0 and v_room then 'hand' when v_left > 0 then 'binder' when rarity = 'common' then 'worn' else 'used' end
    where serial = b.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, case when v_left > 0 then 'card.unequipped' else 'card.worn_out' end, p_user, jsonb_build_object('serial', b.serial, 'card', b.card_id, 'rarity', b.rarity, 'left_s', round(v_left::numeric)));
  if b.card_id = 'veiculo' then perform public.vehicle_card_cleanup(p_user); end if;
end;
$$;
