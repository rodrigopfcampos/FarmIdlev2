-- versão atual (veio de supabase/migrations/20261103000100_v3_card_supply.sql)
create or replace function public.daily_pack_cards(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select coalesce(max((x ->> 1)::int), 1) from jsonb_array_elements(public.config_get('missions') -> 'daily' -> 'pack_cards_by_level') x
  where (x ->> 0)::int <= (select level from public.farms where user_id = p_user)
$$;
