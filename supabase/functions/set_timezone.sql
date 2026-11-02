-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.set_timezone(p_tz text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); pr public.profiles; v_days int := (public.config_get('weather') ->> 'timezone_change_days')::int; cur text; mid timestamptz;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_tz is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) or p_tz !~ '/' then
    raise exception 'fuso horário inválido' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  select * into pr from public.profiles where id = v_user for update;
  cur := public.user_tz(v_user, now());
  if not pr.tz_confirmed then
    update public.profiles set timezone = p_tz, tz_confirmed = true, tz_pending = null, tz_pending_at = null where id = v_user;
    insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'timezone.device', v_user, jsonb_build_object('from', pr.timezone, 'to', p_tz));
  else
    if p_tz = cur and pr.tz_pending is null then raise exception 'esse já é o seu fuso' using errcode = 'check_violation'; end if;
    if pr.tz_changed_at is not null and pr.tz_changed_at > now() - make_interval(days => v_days) then
      raise exception 'o fuso só pode ser trocado 1 vez a cada % dias (de novo em %)', v_days,
        to_char((pr.tz_changed_at + make_interval(days => v_days)) at time zone cur, 'DD/MM HH24:MI') using errcode = 'check_violation';
    end if;
    mid := public.local_instant(cur, (now() at time zone cur)::date + 1, 0);
    update public.profiles set timezone = cur, tz_pending = p_tz, tz_pending_at = mid, tz_changed_at = now() where id = v_user;
    insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'timezone.change', v_user, jsonb_build_object('from', cur, 'to', p_tz, 'from_at', mid));
  end if;
  return public.farm_state(v_user);
end;
$$;
