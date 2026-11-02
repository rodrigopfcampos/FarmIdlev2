-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.weather_now(p_user uuid, p_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  w jsonb := public.config_get('weather'); ev jsonb := w -> 'night_event'; bh int := (w ->> 'block_hours')::int;
  tz text := coalesce(public.user_tz(p_user, p_at), 'America/Sao_Paulo');
  loc timestamp := p_at at time zone tz; d date := loc::date; m int := extract(hour from loc)::int * 60 + extract(minute from loc)::int;
  r public.weather_days; b int := m / (bh * 60); cond text; part text; ef jsonb; ce jsonb := '{}'; e jsonb; evd jsonb;
  st timestamptz; en timestamptz; act boolean := false; nxt timestamptz; last timestamptz; sup boolean := false; xm int;
begin
  -- testes antigos (fases 0–5) desligam o clima para não depender da hora em que rodam
  if current_setting('vif.weather', true) = 'off' then
    return jsonb_build_object('tz', tz, 'day', d, 'minute', m, 'cond', 'sunny', 'part', 'day', 'event', null, 'known', false,
      'next', p_at + interval '1 day', 'cond_fx', jsonb_build_object('growth', 0, 'account_xp', 0, 'char_xp', 0, 'sales', 0));
  end if;
  select * into r from public.weather_days where offset_min = public.tz_offset_min(tz, d) and day = d;
  cond := coalesce(r.blocks[b + 1], 'sunny');
  if m >= public.hm_min(w -> 'day_parts' -> 'day' ->> 0) and m <= public.hm_min(w -> 'day_parts' -> 'day' ->> 1) then part := 'day';
  elsif m >= public.hm_min(w -> 'day_parts' -> 'dusk' ->> 0) and m <= public.hm_min(w -> 'day_parts' -> 'dusk' ->> 1) then part := 'dusk';
  else part := 'night'; end if;
  -- efeitos do clima do bloco e da noite, em fração
  ef := coalesce(w -> 'effects' -> cond, '{}');
  ce := jsonb_build_object(
    'growth', coalesce((ef ->> 'growth_speed_pct')::double precision, 0) / 100,
    'account_xp', coalesce((ef ->> 'account_xp_pct')::double precision, 0) / 100,
    'char_xp', coalesce((ef ->> 'character_xp_pct')::double precision, 0) / 100,
    'sales', case when part = 'night' then coalesce((w -> 'effects' -> 'night' ->> 'sales_gold_pct')::double precision, 0) / 100 else 0 end);
  -- próxima troca: fim do bloco, viradas de dia/entardecer/noite, início e fim do evento
  nxt := public.local_instant(tz, d, (b + 1) * bh * 60);
  foreach xm in array array[public.hm_min(w -> 'day_parts' -> 'day' ->> 0), public.hm_min(w -> 'day_parts' -> 'dusk' ->> 0), public.hm_min(w -> 'day_parts' -> 'night' ->> 0)] loop
    if xm > m then nxt := least(nxt, public.local_instant(tz, d, xm)); end if;
  end loop;
  if r.event_id is not null then
    st := public.local_instant(tz, d, r.event_start_min);
    en := st + make_interval(mins => (ev ->> 'duration_minutes')::int);
    select last_event_start into last from public.farms where user_id = p_user;
    -- no máximo 1 evento por conta a cada 20 h, mesmo trocando de fuso
    sup := last is not null and last <> st and st - last < make_interval(hours => (w ->> 'min_hours_between_events')::int);
    act := not sup and p_at >= st and p_at < en;
    if p_at < st then nxt := least(nxt, st); elsif p_at < en then nxt := least(nxt, en); end if;
    evd := (select x from jsonb_array_elements(ev -> 'events') x where x ->> 'id' = r.event_id);
    e := jsonb_build_object('id', r.event_id, 'name_pt', evd ->> 'name_pt', 'start', st, 'end', en, 'active', act, 'suppressed', sup, 'forced', r.forced,
      'growth', case when act then coalesce((evd ->> 'growth_speed_pct')::double precision, 0) / 100 else 0 end,
      'account_xp', case when act then coalesce((evd ->> 'account_xp_pct')::double precision, 0) / 100 else 0 end,
      'char_xp', case when act then coalesce((evd ->> 'character_xp_pct')::double precision, 0) / 100 else 0 end,
      'moon', case when act then coalesce((evd ->> 'sales_gold_pct')::double precision, 0) / 100 else 0 end);
  end if;
  return jsonb_build_object('tz', tz, 'day', d, 'minute', m, 'cond', cond, 'part', part, 'cond_fx', ce, 'event', e, 'next', nxt, 'known', r.day is not null);
end;
$$;
