-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_player_audit(p_user uuid, p_limit int default 100)
returns setof public.audit_log
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_audit', p_user);
  return query select * from public.audit_log where target_user_id = p_user or actor_id = p_user order by id desc limit least(greatest(p_limit, 1), 500);
end;
$$;
