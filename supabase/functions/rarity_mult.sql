-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.rarity_mult(p_rarity text)
returns double precision
language sql stable
set search_path = ''
as $$
  select coalesce((select (x ->> 'multiplier')::double precision from jsonb_array_elements(public.config_get('rarity') -> 'tiers') x where x ->> 'id' = p_rarity), 1)
$$;
