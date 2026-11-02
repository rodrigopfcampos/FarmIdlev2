-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.local_instant(p_tz text, p_day date, p_min int)
returns timestamptz language sql stable set search_path = '' as $$
  select (p_day + make_interval(mins => p_min)) at time zone p_tz
$$;
