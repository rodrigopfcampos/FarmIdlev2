-- versão atual (veio de supabase/migrations/20261023000100_phase0_base.sql)
create or replace function public.config_get(p_name text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select data from public.game_config where name = p_name order by version desc limit 1
$$;
