-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.account_risk(p_user uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select least(100, coalesce(sum(score), 0))::int from public.alerts
  where user_id = p_user and status <> 'archived'
    and created_at > now() - make_interval(days => (public.config_get('anticheat') ->> 'risk_window_days')::int)
$$;
