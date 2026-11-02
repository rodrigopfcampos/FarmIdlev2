-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.collect_pet(p_pet text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); p public.pets; d jsonb; f public.farms; fac double precision; lv int;
  v_gold numeric := 0; v_energy double precision := 0; v_card bigint; v_card_row public.cards; c public.characters; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into p from public.pets where user_id = v_user and pet_id = p_pet for update;
  if not found then raise exception 'pet ainda não chegou' using errcode = 'check_violation'; end if;
  select * into f from public.farms where user_id = v_user;
  d := public.pet_def(p_pet);
  if f.farm_time < coalesce(p.find_t, f.farm_time) + (d ->> 'find_hours')::double precision * 3600 then
    raise exception 'o achado ainda não está pronto' using errcode = 'check_violation';
  end if;
  fac := public.pet_factor(v_user, p_pet); lv := public.pet_level(v_user, p_pet);
  if d -> 'find' ? 'gold_share_of_R' then
    v_gold := round(public.ref_income(f.level) * (d -> 'find' ->> 'gold_share_of_R')::numeric * fac::numeric, 2);
    if v_gold > 0 then
      perform public.ledger_post(v_user, v_gold, 'pet_find', jsonb_build_object('pet', p_pet, 'level', lv), 'pet:' || p_pet || ':' || round(p.find_t)::text);
      perform public.mission_progress(v_user, 'gold_earned', v_gold);
    end if;
  end if;
  if d -> 'find' ? 'card_chance' and public.rand01() < (d -> 'find' ->> 'card_chance')::double precision
                                                      + (d -> 'find' ->> 'card_chance_per_level')::double precision * (lv - 1) then
    v_card := public.draw_card(v_user, 'pet');
    select * into v_card_row from public.cards where serial = v_card;
  end if;
  if d -> 'find' ? 'team_energy' then
    v_energy := (d -> 'find' ->> 'team_energy')::double precision * fac;
    fx := public.team_fx(v_user);
    for c in select * from public.characters where user_id = v_user for update loop
      update public.characters set energy = least((public.char_energy(c, fx) ->> 'max')::double precision, energy + v_energy),
          parked = case when energy + v_energy >= (public.config_get('characters') -> 'energy' ->> 'parked_until')::double precision then false else parked end
        where user_id = v_user and class_id = c.class_id;
    end loop;
  end if;
  update public.pets set find_t = f.farm_time where user_id = v_user and pet_id = p_pet;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'pet.find', v_user, jsonb_build_object('pet', p_pet, 'level', lv, 'gold', v_gold, 'energy', v_energy, 'card', v_card));
  return public.farm_state(v_user) || jsonb_build_object('pet_find', jsonb_build_object('pet', p_pet, 'gold', v_gold, 'energy', round(v_energy::numeric, 1),
    'card', case when v_card is null then null else jsonb_build_object('serial', v_card, 'card_id', v_card_row.card_id, 'rarity', v_card_row.rarity) end));
end;
$$;
