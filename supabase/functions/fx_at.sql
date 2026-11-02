-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.fx_at()
returns timestamptz language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('vif.at', true), '')::timestamptz, now())
$$;
