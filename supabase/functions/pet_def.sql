-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.pet_def(p_pet text)
returns jsonb language sql stable set search_path = '' as $$
  select x from jsonb_array_elements(public.config_get('characters') -> 'pets' -> 'list') x where x ->> 'id' = p_pet
$$;
