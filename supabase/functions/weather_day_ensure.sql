-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.weather_day_ensure(p_offset int, p_day date, p_depth int default 0)
returns public.weather_days language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.weather_days; prev text; ev jsonb := public.config_get('weather') -> 'night_event'; opts jsonb; n int; st int; steps int;
begin
  select * into r from public.weather_days where offset_min = p_offset and day = p_day;
  if found then return r; end if;
  if p_depth = 0 then prev := (public.weather_day_ensure(p_offset, p_day - 1, 1)).event_id;
  else prev := (select event_id from public.weather_days where offset_min = p_offset and day = p_day - 1); end if;
  select jsonb_agg(x) into opts from jsonb_array_elements(ev -> 'events') x where x ->> 'id' is distinct from prev;
  n := jsonb_array_length(opts);
  steps := (public.hm_min(ev ->> 'start_latest') - public.hm_min(ev -> 'window' ->> 0)) / (ev ->> 'step_minutes')::int + 1;
  st := public.hm_min(ev -> 'window' ->> 0) + floor(public.rand01() * steps)::int * (ev ->> 'step_minutes')::int;
  insert into public.weather_days (offset_min, day, blocks, event_id, event_start_min)
    values (p_offset, p_day, public.weather_gen_blocks(), opts -> floor(public.rand01() * n)::int ->> 'id', st)
    on conflict do nothing;
  select * into r from public.weather_days where offset_min = p_offset and day = p_day;
  return r;
end;
$$;
