-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.class_def(p_class text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('characters') -> 'classes') x where x ->> 'id' = p_class
$$;
