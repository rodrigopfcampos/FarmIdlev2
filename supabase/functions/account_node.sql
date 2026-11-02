-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.account_node(p_node text)
returns jsonb language sql stable set search_path = '' as $$
  select n || jsonb_build_object('branch', b ->> 'id') from jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b,
         jsonb_array_elements(b -> 'nodes') n where n ->> 'id' = p_node limit 1
$$;
