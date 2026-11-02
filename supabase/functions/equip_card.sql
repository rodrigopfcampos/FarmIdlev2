-- versão atual (veio de supabase/migrations/20261105000100_v3_hand_split.sql)
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
