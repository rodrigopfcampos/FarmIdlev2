-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.salary_of(p_user uuid, c public.characters)
returns numeric
language sql stable
set search_path = ''
as $$
  select case when c.class_id = 'agricultor' then 0 else
    round(public.ref_income((select level from public.farms where user_id = p_user))
      * (public.config_get('characters') -> 'salary' ->> 'share_of_R')::numeric
      * (1 + (public.config_get('characters') -> 'salary' ->> 'per_character_level')::numeric * c.level)
      * greatest(0, 1 + public.account_skill(p_user, 'salary_pct')::numeric / 100), 2) end
$$;
