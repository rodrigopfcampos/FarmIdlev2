-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_search_players(p_query text)
returns table (user_id uuid, nickname text, email text, gold numeric, created_at timestamptz, last_activity_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.search', jsonb_build_object('query', left(p_query, 100)));
  return query
    select p.id, p.nickname, u.email::text, w.gold, p.created_at, f.last_activity_at
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.wallets w on w.user_id = p.id
    left join public.farms f on f.user_id = p.id
    where coalesce(p_query, '') = '' or p.nickname ilike '%' || p_query || '%' or u.email ilike '%' || p_query || '%' or p.id::text = p_query
    order by p.created_at desc
    limit 50;
end;
$$;
