-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_route_idx(p_route text)
returns int
language sql stable
set search_path = ''
as $$
  select (o - 1)::int from jsonb_array_elements(public.config_get('expeditions') -> 'routes') with ordinality r(x, o) where x ->> 'id' = p_route
$$;
