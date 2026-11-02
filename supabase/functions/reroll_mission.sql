-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.reroll_mission(p_slot int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); d date; m public.missions; x jsonb; ref jsonb; n_animals int; cfg jsonb := public.config_get('missions');
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  d := public.user_day(v_user, now());
  perform public.mission_ensure(v_user, now());
  if (select reroll_day from public.farms where user_id = v_user) is not distinct from d then
    raise exception 'a troca grátis de hoje já foi usada' using errcode = 'check_violation';
  end if;
  select * into m from public.missions where user_id = v_user and kind = 'daily' and period = d and slot = p_slot for update;
  if not found or m.done_at is not null then raise exception 'missão não pode ser trocada' using errcode = 'check_violation'; end if;
  select count(*) into n_animals from public.animals where user_id = v_user;
  -- outra missão liberada que não esteja na lista de hoje (mesmas regras do sorteio)
  select y into x from jsonb_array_elements(cfg -> 'bank' -> 'daily') y
    where y ->> 'id' not in (select mission_id from public.missions where user_id = v_user and kind = 'daily' and period = d)
      and (coalesce(y ->> 'gate', '') = '' or (y ->> 'gate' = 'animals' and n_animals > 0)
           or (y ->> 'gate' = 'chars3' and (select count(*) from public.characters where user_id = v_user) >= 3)
           or (y ->> 'gate' = 'worn_vehicle' and exists (select 1 from public.vehicles where user_id = v_user and durability < (cfg ->> 'worn_vehicle_below_pct')::double precision)))
    order by public.rand01() limit 1;
  if x is null then raise exception 'não há outra missão disponível' using errcode = 'check_violation'; end if;
  ref := public.prod_ref(v_user);
  update public.missions set mission_id = x ->> 'id', metric = x ->> 'metric', target = public.mission_target(x -> 'target', ref, n_animals), progress = 0
    where user_id = v_user and kind = 'daily' and period = d and slot = p_slot;
  update public.farms set reroll_day = d where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;
