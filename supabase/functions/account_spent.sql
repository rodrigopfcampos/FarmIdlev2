-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.account_spent(p_user uuid, p_branch text default null)
returns int language sql stable set search_path = '' as $$
  select coalesce(sum(coalesce((f.account_skills ->> (n ->> 'id'))::int, 0) * (n ->> 'cost')::int), 0)::int
  from public.farms f, jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b, jsonb_array_elements(b -> 'nodes') n
  where f.user_id = p_user and (p_branch is null or b ->> 'id' = p_branch)
$$;
