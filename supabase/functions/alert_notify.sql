-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.alert_notify(p_alert bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare a public.alerts; v_url text; v_nick text; v_name text;
begin
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null or to_regclass('vault.decrypted_secrets') is null then return false; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1' into v_url using 'discord_alerts_webhook';
  if v_url is null or v_url = '' then return false; end if;
  select * into a from public.alerts where id = p_alert;
  select nickname into v_nick from public.profiles where id = a.user_id;
  v_name := coalesce(public.config_get('anticheat') -> 'rules' -> a.rule ->> 'name_pt', a.rule);
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using v_url,
      jsonb_build_object('username', 'Village Idle Farm', 'content',
        format(E'⚠️ **%s** · %s (nota %s, risco da conta %s)\nJogador: **%s** `%s`\nEvidência: `%s`',
          v_name, case when a.score >= 70 then 'crítico' else 'alerta' end, a.score, a.risk_after, coalesce(v_nick, '?'), a.user_id, left(a.evidence::text, 900))),
      '{"Content-Type": "application/json"}'::jsonb;
  update public.alerts set notified = true where id = p_alert;
  return true;
end;
$$;
