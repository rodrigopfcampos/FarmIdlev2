-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.game_day(p_at timestamptz default now())
returns date
language sql stable
set search_path = ''
as $$
  select (p_at at time zone coalesce(public.config_get('characters') ->> 'payday_timezone', 'America/Sao_Paulo'))::date
$$;
