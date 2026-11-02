-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.care_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_day date := public.game_day(now()); p public.pets;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into p from public.pets where user_id = v_user and pet_id = p_pet for update;
  if not found then raise exception 'pet ainda não chegou' using errcode = 'check_violation'; end if;
  if p.last_care = v_day then raise exception 'carinho de hoje já foi dado' using errcode = 'check_violation'; end if;
  update public.pets set affinity = affinity + 1, last_care = v_day where user_id = v_user and pet_id = p_pet;
  return public.farm_state(v_user);
end;
$$;
