-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.admin_weather(p_tz text, p_day date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); r public.weather_days; d date; out jsonb := '[]';
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then raise exception 'fuso horário inválido' using errcode = 'check_violation'; end if;
  for d in select generate_series(p_day - 1, p_day + 1, interval '1 day')::date loop
    r := public.weather_day_ensure(public.tz_offset_min(p_tz, d), d);
    out := out || jsonb_build_object('day', d, 'offset_min', r.offset_min, 'blocks', to_jsonb(r.blocks), 'event_id', r.event_id, 'forced', r.forced,
      'event_start', case when r.event_id is null then null else public.local_instant(p_tz, d, r.event_start_min) end,
      'event_local', case when r.event_id is null then null else lpad((r.event_start_min / 60)::text, 2, '0') || ':' || lpad((r.event_start_min % 60)::text, 2, '0') end);
  end loop;
  return jsonb_build_object('tz', p_tz, 'days', out);
end;
$$;
