-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.pet_factor(p_user uuid, p_pet text)
returns double precision language sql stable set search_path = '' as $$
  with c as (select public.config_get('characters') -> 'pets' c), l as (select public.pet_level(p_user, p_pet) lv)
  select case when lv = 0 then 0 else (c ->> 'effect_at_level_1')::double precision
           + ((c ->> 'effect_at_level_5')::double precision - (c ->> 'effect_at_level_1')::double precision) * (lv - 1) / 4.0 end
  from c, l
$$;
