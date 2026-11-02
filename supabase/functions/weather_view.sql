-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.weather_view(p_user uuid, fx jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  w jsonb := fx -> 'weather'; bh int := (public.config_get('weather') ->> 'block_hours')::int; tz text := w ->> 'tz'; d date := (w ->> 'day')::date;
  b int := (w ->> 'minute')::int / (bh * 60); r public.weather_days; fc jsonb := '[]'; h double precision := coalesce((fx ->> 'forecast_h')::double precision, 1);
  t timestamptz := now(); k int; dd date; bb int; pr public.profiles; e jsonb := nullif(w -> 'event', 'null'::jsonb); warn int := coalesce((fx ->> 'warn_min')::int, 10);
begin
  -- blocos que começam dentro da janela de previsão (o de agora sempre aparece)
  for k in 0 .. 8 loop
    dd := d + ((b + k) * bh / 24); bb := (b + k) % (24 / bh);
    exit when k > 0 and public.local_instant(tz, dd, bb * bh * 60) > t + make_interval(secs => h * 3600);
    select * into r from public.weather_days where offset_min = public.tz_offset_min(tz, dd) and day = dd;
    fc := fc || jsonb_build_object('from', public.local_instant(tz, dd, bb * bh * 60), 'to', public.local_instant(tz, dd, (bb + 1) * bh * 60), 'cond', coalesce(r.blocks[bb + 1], 'sunny'));
  end loop;
  -- o evento só aparece no aviso (10 min; 30 com o Papagaio) e enquanto dura
  if e is not null and ((e ->> 'suppressed')::boolean or t >= (e ->> 'end')::timestamptz or t < (e ->> 'start')::timestamptz - make_interval(mins => warn)) then e := null; end if;
  select * into pr from public.profiles where id = p_user;
  return jsonb_build_object('tz', tz, 'cond', w ->> 'cond', 'part', w ->> 'part', 'forecast', fc, 'forecast_hours', h, 'warn_minutes', warn,
    'event', case when e is null then null else e - 'growth' - 'account_xp' - 'char_xp' - 'moon' - 'suppressed' end,
    'bonus', jsonb_build_object('growth', fx -> 'w_growth', 'account_xp', fx -> 'w_account_xp', 'char_xp', fx -> 'char_xp', 'sales', fx -> 'w_sales', 'moon', fx -> 'moon'),
    'account', jsonb_build_object('timezone', pr.timezone, 'confirmed', pr.tz_confirmed, 'pending', pr.tz_pending, 'pending_at', pr.tz_pending_at,
      'can_change_at', case when pr.tz_changed_at is null then null
        else pr.tz_changed_at + make_interval(days => (public.config_get('weather') ->> 'timezone_change_days')::int) end));
end;
$$;
