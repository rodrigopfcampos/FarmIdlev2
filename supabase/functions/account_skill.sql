-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.account_skill(p_user uuid, p_effect text)
returns double precision language sql stable set search_path = '' as $$
  select coalesce(sum(coalesce((f.account_skills ->> (n ->> 'id'))::double precision, 0) * (e ->> 'per_point')::double precision), 0)
  from public.farms f, jsonb_array_elements(public.config_get('characters') -> 'account_tree' -> 'branches') b,
       jsonb_array_elements(b -> 'nodes') n, jsonb_array_elements(n -> 'effects') e
  where f.user_id = p_user and e ->> 'effect' = p_effect
$$;
