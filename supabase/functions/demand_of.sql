-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.demand_of(p_day date, p_route text)
returns text[]
language sql stable
set search_path = ''
as $$
  select coalesce((select products from public.daily_demand where day = p_day and route_id = p_route), '{}')
$$;
