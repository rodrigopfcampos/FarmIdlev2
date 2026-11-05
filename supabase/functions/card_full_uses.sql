-- versão atual (nova)
create or replace function public.card_full_uses(p_rarity text)
returns numeric language sql stable set search_path = '' as $$
  -- usos de uma carta inteira pela raridade (Comum 1 … Mítica 5)
  select (public.config_get('cards') -> 'rarities' -> p_rarity ->> 'uses')::numeric
$$;
