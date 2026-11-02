-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.round_rand(p_x double precision)
returns int
language sql volatile
set search_path = ''
as $$
  select floor(p_x + public.rand01())::int
$$;
