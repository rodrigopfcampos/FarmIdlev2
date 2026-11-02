-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.buy_animal(p_house text, p_slot int, p_animal text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); d jsonb := public.animal_def(p_animal); v_time double precision; v_level int;
  v_base int; v_bird int; odds jsonb := public.config_get('rarity') -> 'animals' -> 'purchase_odds';
  u double precision; acc double precision := 0; v_rar text; k text; fx jsonb; v_feed numeric; v_gold numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if d is null or d ->> 'house' <> p_house then raise exception 'animal não é dessa casa' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if not public.house_ready(v_user, p_house, v_time) then raise exception 'casa ainda não existe' using errcode = 'check_violation'; end if;
  if (d ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_base := public.house_slots(v_user, p_house);
  v_bird := public.house_bird_slots(v_user, p_house, v_time);
  if p_slot is null or p_slot < 1 or p_slot > v_base + v_bird then raise exception 'vaga não existe' using errcode = 'check_violation'; end if;
  if p_slot > v_base and not (d ->> 'is_bird')::boolean then raise exception 'vaga do Lago é só para aves' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.animals where user_id = v_user and house_id = p_house and slot = p_slot) then
    raise exception 'vaga ocupada' using errcode = 'check_violation';
  end if;
  perform public.ledger_post(v_user, -(d ->> 'buy_cost')::numeric, 'animal_buy', jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', p_animal));
  -- sorteio criptográfico da raridade, gravado antes de aparecer na tela
  u := public.rand01();
  for k in select x from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) x loop
    acc := acc + coalesce((odds ->> k)::double precision, 0);
    v_rar := k;
    exit when u < acc;
  end loop;
  insert into public.animals (user_id, house_id, slot, animal_id, rarity) values (v_user, p_house, p_slot, p_animal, v_rar);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'animal.bought', v_user, jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', p_animal, 'rarity', v_rar, 'roll', round(u::numeric, 6)));
  fx := public.team_fx(v_user);
  select gold into v_gold from public.wallets where user_id = v_user;
  v_feed := public.animal_start(v_user, p_house, p_slot, v_time, fx, v_gold);
  if v_feed > 0 then perform public.ledger_post(v_user, -v_feed, 'feed', jsonb_build_object('house', p_house, 'slot', p_slot)); end if;
  return public.farm_state(v_user);
end;
$$;
