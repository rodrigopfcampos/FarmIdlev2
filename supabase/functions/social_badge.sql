-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.social_badge(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with f as (select social_seen_at s from public.farms where user_id = p_user)
  select jsonb_build_object('social', jsonb_build_object(
    'incoming', (select count(*) from public.friendships x where (x.user_a = p_user or x.user_b = p_user) and x.status = 'pending' and x.requested_by <> p_user),
    'unseen', (select count(*) from public.lot_helps h, f where h.owner = p_user and h.started_at > f.s)
            + (select count(*) from public.visit_notes n, f where n.to_user = p_user and n.created_at > f.s)
            + (select count(*) from public.farm_likes l, f where l.target = p_user and l.created_at > f.s),
    'helps', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', h.lot_id, 'kind', h.kind, 'pct', h.pct, 'ends_at', h.ends_at,
                'from', (select nickname from public.profiles where id = h.helper)) order by h.ends_at), '[]')
              from public.lot_helps h where h.owner = p_user and h.kind = 'growth' and h.ends_at > now()),
    'likes', (select likes_total from public.farms where user_id = p_user)),
    'village', jsonb_build_object('title', public.village_title(p_user), 'stars', (select stars from public.farms where user_id = p_user)),
    'account', (select jsonb_build_object('status', account_status, 'warning', case when not warning_seen then status_reason end)
                from public.profiles where id = p_user))
$$;
