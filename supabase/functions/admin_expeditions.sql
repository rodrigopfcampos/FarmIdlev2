-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_expeditions()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('route', route_id, 'vehicle', vehicle_id, 'trips', n, 'expected', exp, 'real', real, 'crit', crit) order by route_id, vehicle_id), '[]') from (
    select route_id, vehicle_id, count(*) n, round(avg(chance)::numeric, 3) exp,
      round(avg(case when outcome <> 'fail' then 1 else 0 end)::numeric, 3) real, round(avg(case when outcome = 'crit' then 1 else 0 end)::numeric, 3) crit
    from public.expeditions where status = 'back' group by 1, 2) x);
end;
$$;
