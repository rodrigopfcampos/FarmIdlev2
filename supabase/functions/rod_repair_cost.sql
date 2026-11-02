-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.rod_repair_cost(p_user uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select round((public.material_def(public.tool_tier(f.level)) ->> 'repair_cost_gold')::numeric
    * (1 + (public.team_fx(p_user) ->> 'tool_cost')::numeric) * (1 - (public.team_fx(p_user) ->> 'repair_cut')::numeric)
    * (100 - f.rod_durability)::numeric / 100, 2)
  from public.farms f where f.user_id = p_user
$$;
