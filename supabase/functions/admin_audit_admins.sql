-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_audit_admins(p_limit int default 200)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'at', a.created_at, 'admin', p.nickname, 'action', a.action, 'target', a.target_user_id, 'data', a.data) order by a.id desc), '[]')
    from (select * from public.audit_log where action like 'admin.%' order by id desc limit least(greatest(p_limit, 1), 1000)) a
    left join public.profiles p on p.id = a.actor_id);
end;
$$;
