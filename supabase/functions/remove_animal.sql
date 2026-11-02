-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.remove_animal(p_house text, p_slot int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); a public.animals;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  delete from public.animals where user_id = v_user and house_id = p_house and slot = p_slot returning * into a;
  if not found then raise exception 'vaga vazia' using errcode = 'check_violation'; end if;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'animal.removed', v_user, jsonb_build_object('house', p_house, 'slot', p_slot, 'animal', a.animal_id, 'rarity', a.rarity));
  return public.farm_state(v_user);
end;
$$;
