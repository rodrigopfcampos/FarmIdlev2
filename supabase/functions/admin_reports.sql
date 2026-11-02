-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_reports(p_status text default 'open')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'reporter', pr.nickname, 'target', r.target, 'target_nick', pt.nickname, 'reason', r.reason,
      'status', r.status, 'at', r.created_at, 'note', r.handled_note, 'against', (select count(*) from public.player_reports x where x.target = r.target)) order by r.id desc), '[]')
    from public.player_reports r join public.profiles pr on pr.id = r.reporter join public.profiles pt on pt.id = r.target
    where p_status = 'all' or r.status = p_status);
end;
$$;
