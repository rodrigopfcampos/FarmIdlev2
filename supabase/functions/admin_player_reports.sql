-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_player_reports(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'reporter', p.nickname, 'reason', r.reason, 'at', r.created_at, 'status', r.status) order by r.created_at desc), '[]')
    from public.player_reports r join public.profiles p on p.id = r.reporter where r.target = p_user);
end;
$$;
