-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.tz_offset_min(p_tz text, p_day date)
returns int language sql stable set search_path = '' as $$
  select round(extract(epoch from ((p_day + time '12:00') - (((p_day + time '12:00') at time zone p_tz) at time zone 'UTC'))) / 60)::int
$$;
