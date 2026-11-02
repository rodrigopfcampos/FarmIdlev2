-- versão atual (veio de supabase/migrations/20261023000500_phase2_progression.sql)
create or replace function public.lot_def(p_lot text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = p_lot
$$;
