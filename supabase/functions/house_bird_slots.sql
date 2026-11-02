-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.house_bird_slots(p_user uuid, p_house text, p_t double precision)
returns int
language sql stable
set search_path = ''
as $$
  select case when p_house = 'galinheiro' and public.lake_ready(p_user, p_t)
              then coalesce((public.config_get('animals') -> 'rules' -> 'lake_bonus' ->> 'extra_galinheiro_slots')::int, 0) else 0 end
$$;
