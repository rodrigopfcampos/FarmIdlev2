-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.account_points(p_user uuid)
returns int language sql stable set search_path = '' as $$
  select greatest(0, (f.level - ((t ->> 'from_level')::int - 1)) * (t ->> 'points_per_level')::int)
  from public.farms f, (select public.config_get('characters') -> 'account_tree' t) c where f.user_id = p_user
$$;
