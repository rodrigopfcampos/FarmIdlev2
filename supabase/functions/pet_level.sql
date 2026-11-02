-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.pet_level(p_user uuid, p_pet text)
returns int language sql stable set search_path = '' as $$
  select coalesce((select 1 + (select count(*) from jsonb_array_elements_text(public.config_get('characters') -> 'pets' -> 'affinity_to_level') a
                              where a::int <= p.affinity)::int
                   from public.pets p where p.user_id = p_user and p.pet_id = p_pet), 0)
$$;
