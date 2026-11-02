-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_test_alert()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); v_id bigint; v_sent boolean;
begin
  insert into public.alerts (user_id, rule, score, evidence, status, risk_after)
    values (v_admin, 'test', 0, jsonb_build_object('teste', 'alerta de teste do painel'), 'archived', 0) returning id into v_id;
  v_sent := public.alert_notify(v_id);
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.test_alert', jsonb_build_object('alert', v_id, 'sent', v_sent));
  return jsonb_build_object('alert', v_id, 'sent', v_sent);
end;
$$;
