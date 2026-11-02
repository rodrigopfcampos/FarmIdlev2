-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.seed_price(p_crop text, fx jsonb)
returns numeric
language sql stable
set search_path = ''
as $$
  select round((public.crop_def(p_crop) ->> 'seed_cost')::numeric * (1 - (fx ->> 'seed_discount')::numeric), 2)
$$;
