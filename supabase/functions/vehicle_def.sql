-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.vehicle_def(p_vehicle text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x where x ->> 'id' = p_vehicle
$$;
