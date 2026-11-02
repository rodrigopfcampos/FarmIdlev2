-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_cargo_value(p_cargo jsonb, p_route text, p_day date)
returns numeric
language sql stable
set search_path = ''
as $$
  select coalesce(round(sum(c.value::numeric * public.item_price(c.key) * (public.exp_route(p_route) ->> 'price_multiplier')::numeric
           * case when c.key = any (public.demand_of(p_day, p_route)) then 1 + (public.config_get('expeditions') -> 'daily_demand' ->> 'bonus')::numeric else 1 end), 2), 0)
  from jsonb_each_text(p_cargo) c
$$;
