-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.rand01()
returns double precision
language sql volatile
set search_path = ''
as $$
  select (('x' || encode(extensions.gen_random_bytes(7), 'hex'))::bit(56)::bigint)::double precision / 72057594037927936.0
$$;
