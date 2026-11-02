-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.ref_income(p_level int)
returns numeric
language sql stable
set search_path = ''
as $$
  select (public.config_get('levels') -> 'levels' -> (greatest(1, least(50, p_level)) - 1) ->> 'reference_income_per_day')::numeric
$$;
