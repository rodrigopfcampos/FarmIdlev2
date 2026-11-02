-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_player_farm(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_farm', p_user);
  return public.farm_state(p_user);
end;
$$;
