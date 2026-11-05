-- versão atual (veio de supabase/migrations/20261105000100_v3_hand_split.sql)
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
