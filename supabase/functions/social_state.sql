-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.social_state(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('social') cfg),
  d as (select public.user_day(p_user, now()) d),
  fr as (select case when x.user_a = p_user then x.user_b else x.user_a end other, x.status, x.requested_by, x.created_at
         from public.friendships x where x.user_a = p_user or x.user_b = p_user),
  act as (
    select 'help' kind, h.helper who, h.started_at at, jsonb_build_object('lot', h.lot_id, 'help', h.kind, 'pct', h.pct) extra
      from public.lot_helps h, c where h.owner = p_user and h.started_at > now() - make_interval(days => (c.cfg ->> 'activity_days')::int)
    union all
    select 'like', l.liker, l.created_at, '{}'::jsonb from public.farm_likes l, c where l.target = p_user and l.created_at > now() - make_interval(days => (c.cfg ->> 'activity_days')::int)
    union all
    select 'note', n.from_user, n.created_at, jsonb_build_object('emojis', to_jsonb(n.emojis))
      from public.visit_notes n, c where n.to_user = p_user and n.created_at > now() - make_interval(days => (c.cfg -> 'notes' ->> 'keep_days')::int)
  )
  select jsonb_build_object(
    'friends', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'accepted'),
    'incoming', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'pending' and fr.requested_by <> p_user),
    'outgoing', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'pending' and fr.requested_by = p_user),
    'blocked', (select coalesce(jsonb_agg(public.player_card(b.blocked_id) order by b.created_at), '[]') from public.blocks b where b.user_id = p_user),
    'activity', (select coalesce(jsonb_agg(x order by x ->> 'at' desc), '[]') from (
        select jsonb_build_object('kind', a.kind, 'from', public.player_card(a.who), 'at', a.at, 'new', a.at > (select social_seen_at from public.farms where user_id = p_user)) || a.extra x
        from act a, c where not public.social_blocked(p_user, a.who) order by a.at desc limit (select (cfg ->> 'activity_max')::int from c)) y),
    'helps_given', (select count(*) from public.lot_helps h, d where h.helper = p_user and h.given_day = d.d),
    'helps_received', (select count(*) from public.lot_helps h, d where h.owner = p_user and h.received_day = d.d),
    'likes', (select likes_total from public.farms where user_id = p_user))
$$;
