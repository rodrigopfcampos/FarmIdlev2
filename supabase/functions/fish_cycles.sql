-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.fish_cycles(p_user uuid, p_t double precision)
returns int language sql stable set search_path = '' as $$
  select case when f.fish_t is null or not public.lake_ready(p_user, p_t) then 0
    else least((c ->> 'max_cycles')::int, floor(greatest(0, p_t - f.fish_t) / ((c ->> 'cycle_minutes')::double precision * 60))::int) end
  from public.farms f, (select public.config_get('fishing') c) cfg where f.user_id = p_user
$$;
