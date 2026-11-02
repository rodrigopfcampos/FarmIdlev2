-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_player_summary(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select jsonb_build_object(
    'id', p.id, 'nickname', p.nickname, 'created_at', p.created_at, 'timezone', p.timezone,
    'status', p.account_status, 'status_until', p.status_until, 'status_reason', p.status_reason,
    'role', case when p.is_admin then 'admin' else p.admin_role end, 'market_frozen', p.market_frozen,
    'risk', public.account_risk(p.id),
    'alerts', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'rule', a.rule, 'score', a.score, 'status', a.status, 'at', a.created_at, 'evidence', a.evidence) order by a.id desc), '[]')
               from (select * from public.alerts where user_id = p.id order by id desc limit 30) a),
    'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'actions', d.actions) order by d.day desc), '[]')
             from (select * from public.farm_days where user_id = p.id order by day desc limit 30) d),
    'cards', (select coalesce(jsonb_object_agg(r, n), '{}') from (select rarity r, count(*) n from public.cards where user_id = p.id group by rarity) x),
    'cards_by_origin', (select coalesce(jsonb_object_agg(o, n), '{}') from (select origin o, count(*) n from public.cards where user_id = p.id group by origin) x),
    'armory', (select count(*) from public.armory where user_id = p.id),
    'stars', (select stars from public.farms where user_id = p.id),
    'friends', (select count(*) from public.friendships where (user_a = p.id or user_b = p.id) and status = 'accepted'),
    'reports_against', (select count(*) from public.player_reports where target = p.id))
    from public.profiles p where p.id = p_user);
end;
$$;
