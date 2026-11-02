-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.admin_force_event(p_tz text, p_day date, p_event text, p_start_hm text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); ev jsonb := public.config_get('weather') -> 'night_event'; m int; off int; r public.weather_days;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then raise exception 'fuso horário inválido' using errcode = 'check_violation'; end if;
  if p_event is not null and not exists (select 1 from jsonb_array_elements(ev -> 'events') x where x ->> 'id' = p_event) then
    raise exception 'evento desconhecido' using errcode = 'check_violation';
  end if;
  off := public.tz_offset_min(p_tz, p_day);
  r := public.weather_day_ensure(off, p_day);
  m := case when p_start_hm is null then r.event_start_min else public.hm_min(p_start_hm) end;
  if m is null or m < 0 or m + (ev ->> 'duration_minutes')::int > 24 * 60 or m % (ev ->> 'step_minutes')::int <> 0 then
    raise exception 'horário inválido (passos de % min, terminando até 24:00)', ev ->> 'step_minutes' using errcode = 'check_violation';
  end if;
  update public.weather_days set event_id = p_event, event_start_min = m, forced = true where offset_min = off and day = p_day;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, case when p_event is null then 'admin.cancel_event' else 'admin.force_event' end, null,
      jsonb_build_object('tz', p_tz, 'offset_min', off, 'day', p_day, 'event', p_event, 'start_min', m, 'before', r.event_id, 'before_start_min', r.event_start_min, 'reason', p_reason));
  return public.admin_weather(p_tz, p_day);
end;
$$;
