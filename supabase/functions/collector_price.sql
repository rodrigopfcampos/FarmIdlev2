-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.collector_price(p_user uuid, p_rarity text)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(public.ref_income(f.level) * (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'collector_sell_reference_income_ratio')::numeric, 2)
  from public.farms f where f.user_id = p_user
$$;
