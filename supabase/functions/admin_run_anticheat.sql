-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_run_anticheat(p_user uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('moderator'); u uuid; n int := 0; k int := 0;
begin
  for u in select user_id from public.farms where (p_user is null and last_activity_at > now() - interval '30 days') or user_id = p_user loop
    n := n + public.anticheat_check(u, true); k := k + 1;
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.run_anticheat', p_user, jsonb_build_object('accounts', k, 'alerts', n));
  return jsonb_build_object('accounts', k, 'alerts', n);
end;
$$;
