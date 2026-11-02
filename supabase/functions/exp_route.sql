-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_route(p_route text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('expeditions') -> 'routes') x where x ->> 'id' = p_route
$$;
