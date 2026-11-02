-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.material_idx(p_material text)
returns int
language sql stable
set search_path = ''
as $$
  select (ord - 1)::int from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') with ordinality m(x, ord)
  where x ->> 'id' = coalesce(p_material, 'wood')
$$;
