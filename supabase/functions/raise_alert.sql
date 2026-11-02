-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.raise_alert(p_user uuid, p_rule text, p_evidence jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare c jsonb := public.config_get('anticheat'); v_score int; v_id bigint; v_risk int;
begin
  v_score := coalesce((c -> 'rules' -> p_rule ->> 'score')::int, 0);
  if exists (select 1 from public.alerts where user_id = p_user and rule = p_rule
             and created_at > now() - make_interval(hours => (c ->> 'dedupe_hours')::int)) then return null; end if;
  insert into public.alerts (user_id, rule, score, evidence) values (p_user, p_rule, v_score, coalesce(p_evidence, '{}')) returning id into v_id;
  v_risk := public.account_risk(p_user);
  update public.alerts set risk_after = v_risk where id = v_id;
  if v_risk >= (c ->> 'freeze_market_from')::int then update public.profiles set market_frozen = true where id = p_user; end if;
  if v_score > 0 and v_risk >= (c ->> 'notify_from')::int then perform public.alert_notify(v_id); end if;
  return v_id;
end;
$$;
