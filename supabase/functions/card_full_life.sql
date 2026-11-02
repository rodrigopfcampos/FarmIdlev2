-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.card_full_life(p_rarity text)
returns double precision language sql stable set search_path = '' as $$
  select (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'duration_days')::double precision * 86400
$$;
