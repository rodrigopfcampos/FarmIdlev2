-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.card_def(p_card text)
returns jsonb language sql stable set search_path = '' as $$
  select x from jsonb_array_elements(public.config_get('cards') -> 'cards') x where x ->> 'id' = p_card
$$;
