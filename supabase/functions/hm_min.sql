-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.hm_min(p_hm text)
returns int language sql immutable set search_path = '' as $$
  select split_part(p_hm, ':', 1)::int * 60 + split_part(p_hm, ':', 2)::int
$$;
