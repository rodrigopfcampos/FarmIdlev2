-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.pet_info(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when count(*) = 0 then null else jsonb_build_object('level', max(public.pet_level(p_user, p.pet_id)), 'count', count(*)) end
  from public.pets p where p.user_id = p_user
$$;
