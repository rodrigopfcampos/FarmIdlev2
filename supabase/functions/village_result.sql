-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_result(p_order bigint, p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('village') -> 'encomenda' e),
  o as (select * from public.village_orders where id = p_order),
  tot as (select user_id, sum(points) pts from public.village_donations where order_id = p_order group by user_id),
  q as (select tot.* from tot, c where tot.pts >= (c.e ->> 'min_points_to_qualify')::numeric),
  r as (select user_id, pts, rank() over (order by pts desc) rk, count(*) over () n from q)
  select jsonb_build_object(
    'points', coalesce((select pts from tot where user_id = p_user), 0),
    'total', coalesce((select sum(pts) from tot), 0),
    'donors', (select count(*) from tot),
    'goal_reached', coalesce((select sum(pts) from tot), 0) >= (select goal from o),
    'qualified', exists (select 1 from q where user_id = p_user),
    'rank', (select rk from r where user_id = p_user),
    'top', coalesce((select rk <= greatest(1, ceil(n * (select (e ->> 'top_pct')::numeric from c) / 100)) from r where user_id = p_user), false))
$$;
