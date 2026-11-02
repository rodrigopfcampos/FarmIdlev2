-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_overview()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader'); d date := (now() at time zone 'UTC')::date; ign text[];
begin
  ign := array(select jsonb_array_elements_text(public.config_get('anticheat') -> 'rules' -> 'income' -> 'ignore_reasons'));
  return jsonb_build_object(
    'online', (select count(*) from public.farms where last_activity_at > now() - interval '5 minutes'),
    'dau', (select count(*) from public.farm_days where day = d),
    'wau', (select count(distinct user_id) from public.farm_days where day > d - 7),
    'mau', (select count(distinct user_id) from public.farm_days where day > d - 30),
    'players', (select count(*) from public.farms),
    'new_today', (select count(*) from public.profiles where created_at >= d),
    'new_7d', (select count(*) from public.profiles where created_at >= d - 6),
    'retention', (select jsonb_object_agg('D' || k, (select case when count(*) = 0 then null else round(avg(case when exists (
          select 1 from public.farm_days fd where fd.user_id = p.id and fd.day = (p.created_at at time zone 'UTC')::date + k) then 1 else 0 end)::numeric, 3) end
        from public.profiles p where (p.created_at at time zone 'UTC')::date between d - k - 30 and d - k))
      from unnest(array[1, 7, 30]) k),
    'gold_created_today', (select coalesce(sum(amount), 0) from public.ledger where amount > 0 and created_at >= d and not (reason = any (ign))),
    'gold_destroyed_today', (select coalesce(-sum(amount), 0) from public.ledger where amount < 0 and created_at >= d),
    'gold_circulating', (select coalesce(sum(gold), 0) from public.wallets),
    'alerts_open', (select count(*) from public.alerts where status = 'open' and score > 0),
    'alerts_review', (select count(distinct user_id) from public.alerts where status = 'open' and risk_after >= (public.config_get('anticheat') ->> 'review_from')::int),
    'reports_open', (select count(*) from public.player_reports where status = 'open'));
end;
$$;
