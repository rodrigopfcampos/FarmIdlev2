-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.hand_slots(p_level int)
returns int language sql stable set search_path = '' as $$
  select coalesce(max((x ->> 1)::int), 0) from jsonb_array_elements(public.config_get('cards') -> 'rules' -> 'hand' -> 'slots_by_level') x
  where (x ->> 0)::int <= p_level
$$;
