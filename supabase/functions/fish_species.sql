-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.fish_species(p_level int)
returns jsonb language sql stable set search_path = '' as $$
  select x from jsonb_array_elements(public.config_get('fishing') -> 'species') x
  where (x ->> 'unlock_level')::int <= p_level order by (x ->> 'unlock_level')::int desc limit 1
$$;
