-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.mission_week(p_day date)
returns date language sql immutable set search_path = '' as $$
  select p_day - (extract(isodow from p_day)::int - 1)
$$;
