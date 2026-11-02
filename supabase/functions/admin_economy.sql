-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_economy(p_days int default 14)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return jsonb_build_object(
    'by_reason', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'reason', reason, 'in', gin, 'out', gout) order by day desc, reason), '[]') from (
      select (created_at at time zone 'UTC')::date as day, reason, sum(greatest(amount, 0)) as gin, -sum(least(amount, 0)) as gout
      from public.ledger where created_at > now() - make_interval(days => least(greatest(p_days, 1), 90)) group by 1, 2) x),
    'circulating', (select coalesce(sum(gold), 0) from public.wallets),
    'income_by_level', (select coalesce(jsonb_agg(jsonb_build_object('level', level, 'players', n, 'p50', p50, 'p90', p90, 'R', public.ref_income(level)) order by level), '[]') from (
      select f.level, count(*) n, percentile_cont(0.5) within group (order by g.v) p50, percentile_cont(0.9) within group (order by g.v) p90
      from public.farms f join lateral (select coalesce(sum(amount), 0) v from public.ledger l where l.user_id = f.user_id and l.amount > 0
        and l.created_at > now() - interval '24 hours' and l.reason not in ('test_grant', 'admin_grant')) g on true
      group by f.level) y));
end;
$$;
