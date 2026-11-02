-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.tool_tier(p_level int)
returns text language sql stable set search_path = '' as $$
  select x ->> 'id' from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') x
  where (x ->> 'unlock_level')::int <= p_level order by (x ->> 'unlock_level')::int desc limit 1
$$;
