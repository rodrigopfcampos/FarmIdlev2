-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.fish_state(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when f.fish_t is null or not public.lake_ready(p_user, f.farm_time) then null else jsonb_build_object(
    'cycles', public.fish_cycles(p_user, f.farm_time), 'max', (c ->> 'max_cycles')::int,
    'fish_t', f.fish_t, 'cycle_s', (c ->> 'cycle_minutes')::int * 60, 'species', public.fish_species(f.level) ->> 'id',
    'rod', round(f.rod_durability::numeric, 1), 'rod_repair', public.rod_repair_cost(p_user)) end
  from public.farms f, (select public.config_get('fishing') c) cfg where f.user_id = p_user
$$;
