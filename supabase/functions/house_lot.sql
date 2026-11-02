-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.house_lot(p_house text)
returns text
language sql stable
set search_path = ''
as $$
  select x ->> 'id' from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x
  where x ->> 'type' = public.config_get('animals') -> 'houses' -> p_house ->> 'lot_type' limit 1
$$;
