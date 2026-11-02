-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.upgrade_house(p_house text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_tier int; v_next jsonb; v_level int; v_time double precision; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.config_get('animals') -> 'houses' -> p_house is null then raise exception 'casa não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if not public.house_ready(v_user, p_house, v_time) then raise exception 'casa ainda não existe' using errcode = 'check_violation'; end if;
  insert into public.animal_houses (user_id, house_id) values (v_user, p_house) on conflict do nothing;
  select tier into v_tier from public.animal_houses where user_id = v_user and house_id = p_house for update;
  v_next := public.config_get('animals') -> 'houses' -> p_house -> 'slots' -> (v_tier + 1);
  if v_next is null then raise exception 'casa já está no máximo' using errcode = 'check_violation'; end if;
  if v_level < (v_next ->> 'min_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_cost := round((v_next ->> 'cost')::numeric * (1 + (public.team_fx(v_user) ->> 'expansion_cost')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'house_upgrade', jsonb_build_object('house', p_house, 'slots', v_next -> 'slots'), 'house:' || p_house || ':' || (v_tier + 1));
  update public.animal_houses set tier = v_tier + 1 where user_id = v_user and house_id = p_house;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'house.upgraded', v_user, jsonb_build_object('house', p_house, 'tier', v_tier + 1, 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;
