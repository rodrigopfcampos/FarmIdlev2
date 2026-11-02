-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.nice_round(p numeric)
returns numeric language sql immutable set search_path = '' as $$
  select case when p <= 0 then 0 else round(p / power(10, floor(log(p)) - 1)) * power(10, floor(log(p)) - 1) end
$$;
