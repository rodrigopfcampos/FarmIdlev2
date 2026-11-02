-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.animal_def(p_animal text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('animals') -> 'animals') x where x ->> 'id' = p_animal
$$;
