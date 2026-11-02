-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_capacity(v public.vehicles, p_lead jsonb)
returns int
language sql stable
set search_path = ''
as $$
  select floor((public.vehicle_def(v.vehicle_id) ->> 'capacity')::double precision * public.rarity_mult(v.rarity)
               * (1 + coalesce((p_lead ->> 'capacity_pct')::double precision, 0) / 100))::int
$$;
