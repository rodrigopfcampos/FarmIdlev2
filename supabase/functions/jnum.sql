-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.jnum(p jsonb, k text)
returns double precision language sql immutable set search_path = '' as $$
  select coalesce((p ->> k)::double precision, 0)
$$;
