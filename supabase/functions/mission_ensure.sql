-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.mission_ensure(p_user uuid, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  cfg jsonb := public.config_get('missions'); d date := public.user_day(p_user, p_at); w date; k text; per date; ref jsonb; m record; i int;
  v_level int; n_animals int; n_chars int; worn boolean; far boolean;
begin
  w := public.mission_week(d);
  if exists (select 1 from public.missions where user_id = p_user and kind = 'daily' and period = d)
     and exists (select 1 from public.missions where user_id = p_user and kind = 'weekly' and period = w) then return; end if;
  perform public.prod_roll(p_user, d);
  select level into v_level from public.farms where user_id = p_user;
  select count(*) into n_animals from public.animals where user_id = p_user;
  select count(*) into n_chars from public.characters where user_id = p_user;
  worn := exists (select 1 from public.vehicles where user_id = p_user and durability < (cfg ->> 'worn_vehicle_below_pct')::double precision);
  far := v_level >= coalesce((public.exp_route(cfg ->> 'far_route') ->> 'unlock_level')::int, 999);
  ref := public.prod_ref(p_user);
  foreach k in array array['daily', 'weekly'] loop
    per := case when k = 'daily' then d else w end;
    continue when exists (select 1 from public.missions where user_id = p_user and kind = k and period = per);
    i := 0;
    for m in
      select x from jsonb_array_elements(cfg -> 'bank' -> k) x
      where coalesce(x ->> 'gate', '') = '' or (x ->> 'gate' = 'animals' and n_animals > 0) or (x ->> 'gate' = 'chars3' and n_chars >= 3)
            or (x ->> 'gate' = 'worn_vehicle' and worn) or (x ->> 'gate' = 'capital' and far)
      order by public.rand01()
      limit (cfg -> k ->> 'count')::int
    loop
      i := i + 1;
      insert into public.missions (user_id, kind, period, slot, mission_id, metric, target, reward)
        values (p_user, k, per, i, m.x ->> 'id', m.x ->> 'metric', public.mission_target(m.x -> 'target', ref, n_animals),
          case when k = 'daily' then jsonb_build_object(
            'gold', round((cfg -> 'daily' ->> 'gold_hours_of_income')::numeric * (ref ->> 'value_h')::numeric, 2),
            'xp', round((cfg -> 'daily' ->> 'xp_hours_of_production')::numeric * (ref ->> 'xp_h')::numeric, 2)) else '{}' end)
        on conflict do nothing;
    end loop;
    insert into public.mission_weeks (user_id, week) values (p_user, w) on conflict do nothing;
  end loop;
end;
$$;
