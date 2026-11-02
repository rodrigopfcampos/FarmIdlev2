-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.exp_chance(p_user uuid, v vehicles, p_route text, p_lead jsonb, p_minigame text, fx jsonb)
 RETURNS double precision
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with e as (select public.config_get('expeditions') c)
  select greatest(0, least((c ->> 'success_cap')::double precision,
    (public.exp_route(p_route) ->> 'success')::double precision
    + ((public.vehicle_def(v.vehicle_id) ->> 'safety_pts')::double precision * public.rarity_mult(v.rarity)
       + coalesce((c -> 'minigame' -> 'result_pts' ->> p_minigame)::double precision, 0)
       + coalesce((p_lead ->> 'success_pts')::double precision, 0)
       + coalesce((fx ->> 'exp_success')::double precision, 0)
       + case fx -> 'weather' ->> 'cond'
           when 'rain' then case when v.vehicle_id = 'carroca' then (c -> 'weather_success_pts' ->> 'cart_in_rain')::double precision
                                 else (c -> 'weather_success_pts' ->> 'rain')::double precision end
           when 'fog' then (c -> 'weather_success_pts' ->> 'fog')::double precision else 0 end
       + case when fx -> 'weather' ->> 'part' = 'night' then (c -> 'weather_success_pts' ->> 'night')::double precision else 0 end
       + case when v.durability < (c ->> 'low_wear_threshold_pct')::double precision then (c ->> 'low_wear_success_pts')::double precision else 0 end
       + case when (select exp_fail_streak from public.farms where user_id = p_user) >= (c -> 'bad_luck_protection' ->> 'after_failures')::int
              then (c -> 'bad_luck_protection' ->> 'bonus_pts')::double precision else 0 end) / 100))
  from e
$function$;
