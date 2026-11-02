-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.vehicle_price(p_vehicle text)
returns numeric
language sql stable
set search_path = ''
as $$
  select case when (d ->> 'cost')::numeric > 0 then (d ->> 'cost')::numeric else coalesce((d ->> 'reference_cost')::numeric, 0) end
  from (select public.vehicle_def(p_vehicle) d) x
$$;
