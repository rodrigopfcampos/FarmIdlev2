-- versão atual (veio de supabase/migrations/20261105000100_v3_hand_split.sql)
create or replace function public.hand_count(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select count(*)::int from public.cards where user_id = p_user and state = 'hand'
$$;
