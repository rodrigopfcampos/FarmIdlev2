-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.card_repair_cost(p_user uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(public.ref_income(f.level) * (public.config_get('cards') -> 'rarities' -> 'common' -> 'repair' ->> 'cost_reference_income_ratio')::numeric, 2)
  from public.farms f where f.user_id = p_user
$$;
