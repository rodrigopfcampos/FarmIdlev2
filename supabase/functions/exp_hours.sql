-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_hours(v public.vehicles, p_route text, p_lead jsonb, fx jsonb)
returns double precision
language sql stable
set search_path = ''
as $$
  select (public.exp_route(p_route) ->> 'hours')::double precision * (public.vehicle_def(v.vehicle_id) ->> 'duration_multiplier')::double precision
         / public.rarity_mult(v.rarity) * coalesce((p_lead ->> 'duration_mult')::double precision, 1)
         * (1 + coalesce((fx ->> 'exp_duration')::double precision, 0))
$$;
