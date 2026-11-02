-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.material_def(p_material text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') x where x ->> 'id' = coalesce(p_material, 'wood')
$$;
