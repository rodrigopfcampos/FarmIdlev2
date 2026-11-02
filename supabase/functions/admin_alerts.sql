-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_alerts(p_status text default 'open', p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(x order by (x ->> 'risk')::int desc, (x ->> 'id')::bigint desc), '[]') from (
    select jsonb_build_object('id', a.id, 'user_id', a.user_id, 'nickname', p.nickname, 'rule', a.rule, 'score', a.score, 'risk', public.account_risk(a.user_id),
      'status', a.status, 'evidence', a.evidence, 'at', a.created_at, 'notified', a.notified, 'note', a.review_note) x
    from public.alerts a join public.profiles p on p.id = a.user_id
    where p_status = 'all' or a.status = p_status
    order by a.id desc limit least(greatest(p_limit, 1), 500)) y);
end;
$$;
