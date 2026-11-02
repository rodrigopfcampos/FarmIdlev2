-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.moon_bonus(p_user uuid, p_amount numeric, fx jsonb)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare
  m numeric := coalesce((fx ->> 'moon')::numeric, 0); st timestamptz; cap numeric; paid numeric; prev timestamptz; lvl int; b numeric;
  ratio numeric := (select (x ->> 'cap_R_ratio')::numeric from jsonb_array_elements(public.config_get('weather') -> 'night_event' -> 'events') x where x ->> 'id' = 'lua_cheia');
begin
  if m <= 0 or coalesce(p_amount, 0) <= 0 then return 0; end if;
  st := (fx -> 'weather' -> 'event' ->> 'start')::timestamptz;
  select moon_start, moon_paid, level into prev, paid, lvl from public.farms where user_id = p_user for update;
  if prev is distinct from st then paid := 0; end if;
  cap := public.ref_income(lvl) * ratio;
  b := round(greatest(0, least(p_amount * m, cap - paid)), 2);
  update public.farms set moon_start = st, moon_paid = paid + b where user_id = p_user;
  return b;
end;
$$;
