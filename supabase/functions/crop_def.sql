-- versão atual (veio de supabase/migrations/20261023000300_phase1_farm.sql)
create or replace function public.crop_def(p_crop text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('crops') -> 'crops') x where x ->> 'id' = p_crop
$$;
