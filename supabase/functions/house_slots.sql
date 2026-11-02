-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.house_slots(p_user uuid, p_house text)
returns int
language sql stable
set search_path = ''
as $$
  select (public.config_get('animals') -> 'houses' -> p_house -> 'slots'
          -> coalesce((select tier from public.animal_houses where user_id = p_user and house_id = p_house), 0) ->> 'slots')::int
$$;
