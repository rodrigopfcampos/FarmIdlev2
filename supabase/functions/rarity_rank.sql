-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.rarity_rank(p_rarity text)
returns int language sql immutable set search_path = '' as $$
  select array_position(array['common', 'uncommon', 'rare', 'legendary', 'mythic'], p_rarity)
$$;
