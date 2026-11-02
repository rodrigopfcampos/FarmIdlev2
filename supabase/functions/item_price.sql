-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.item_price(p_item text)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce((public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric,
    (select (x -> 'product' ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('animals') -> 'animals') x
     where x -> 'product' ->> 'id' = p_item limit 1),
    (select (x ->> 'fair_price_per_unit')::numeric from jsonb_array_elements(public.config_get('fishing') -> 'species') x where x ->> 'id' = p_item limit 1))
$$;
