-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_missions()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', mission_id, 'kind', kind, 'drawn', n, 'done', d, 'rate', round(d::numeric / n, 3), 'avg_hours', h) order by kind, mission_id), '[]') from (
    select mission_id, kind, count(*) n, count(done_at) d,
      round((avg(extract(epoch from (done_at - period::timestamptz)) / 3600) filter (where done_at is not null))::numeric, 1) h
    from public.missions group by 1, 2) x);
end;
$$;
