-- Fase 6: clima por fuso, dia e noite, evento noturno, troca de fuso e painel.
-- Regras na GDD seção 10; números em config/weather.json (lidos do banco com config_get).

-- ---------- tabelas ----------
-- agenda do dia por deslocamento do fuso (todos do mesmo fuso veem o mesmo clima e o mesmo evento); fica guardada para o painel
create table if not exists public.weather_days (
  offset_min int not null,
  day date not null,
  blocks text[] not null,              -- 8 blocos de 3 h (00–03, 03–06, … 21–24)
  event_id text,                       -- null = sem evento (cancelado pelo painel)
  event_start_min int,                 -- minutos depois da meia-noite local
  forced boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (offset_min, day)
);
alter table public.weather_days enable row level security;  -- só as funções do servidor leem

alter table public.profiles add column if not exists tz_confirmed boolean not null default false;  -- já veio do aparelho?
alter table public.profiles add column if not exists tz_changed_at timestamptz;                    -- última troca feita pelo jogador
alter table public.profiles add column if not exists tz_pending text;                               -- fuso novo, vale na próxima meia-noite
alter table public.profiles add column if not exists tz_pending_at timestamptz;
alter table public.farms add column if not exists last_event_start timestamptz;  -- início do último evento que valeu (1 a cada 20 h)
alter table public.farms add column if not exists moon_start timestamptz;        -- Lua Cheia: evento e ouro extra já pago nele
alter table public.farms add column if not exists moon_paid numeric(18,2) not null default 0;

-- ---------- fuso ----------
create or replace function public.user_tz(p_user uuid, p_at timestamptz default now())
returns text language sql stable security definer set search_path = '' as $$
  select case when pr.tz_pending is not null and p_at >= pr.tz_pending_at then pr.tz_pending else pr.timezone end
  from public.profiles pr where pr.id = p_user
$$;

-- dia do jogo no fuso da conta (salários e virada do dia)
create or replace function public.user_day(p_user uuid, p_at timestamptz default now())
returns date language sql stable security definer set search_path = '' as $$
  select (p_at at time zone coalesce(public.user_tz(p_user, p_at), 'America/Sao_Paulo'))::date
$$;

-- deslocamento do fuso em minutos naquele dia (meio-dia local; horário de verão vem do próprio padrão IANA)
create or replace function public.tz_offset_min(p_tz text, p_day date)
returns int language sql stable set search_path = '' as $$
  select round(extract(epoch from ((p_day + time '12:00') - (((p_day + time '12:00') at time zone p_tz) at time zone 'UTC'))) / 60)::int
$$;

-- instante real de "dia + minutos" no relógio local do fuso
create or replace function public.local_instant(p_tz text, p_day date, p_min int)
returns timestamptz language sql stable set search_path = '' as $$
  select (p_day + make_interval(mins => p_min)) at time zone p_tz
$$;

create or replace function public.hm_min(p_hm text)
returns int language sql immutable set search_path = '' as $$
  select split_part(p_hm, ':', 1)::int * 60 + split_part(p_hm, ':', 2)::int
$$;

-- relógio das bonificações: dentro de advance_farm é o instante do passo; fora, agora
create or replace function public.fx_at()
returns timestamptz language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('vif.at', true), '')::timestamptz, now())
$$;

-- ---------- sorteio do dia ----------
create or replace function public.weather_gen_blocks()
returns text[] language plpgsql volatile security definer set search_path = '' as $$
declare
  w jsonb := public.config_get('weather'); bh int := (w ->> 'block_hours')::int; n int := 24 / bh;
  out text[] := '{}'; b int; tot double precision; u double precision; acc double precision; k record; lim jsonb; pick text;
begin
  for b in 0 .. n - 1 loop
    -- tipos que podem cair neste bloco (Sol forte 09–18, Neblina 03–12); as chances dos outros são redistribuídas
    tot := 0;
    for k in select key, value::double precision v from jsonb_each_text(w -> 'chances') loop
      lim := w -> 'limits' -> k.key;
      if lim is null or (b * bh * 60 >= public.hm_min(lim ->> 0) and (b + 1) * bh * 60 <= public.hm_min(lim ->> 1)) then tot := tot + k.v; end if;
    end loop;
    u := public.rand01() * tot; acc := 0; pick := null;
    for k in select key, value::double precision v from jsonb_each_text(w -> 'chances') order by key loop
      lim := w -> 'limits' -> k.key;
      if lim is null or (b * bh * 60 >= public.hm_min(lim ->> 0) and (b + 1) * bh * 60 <= public.hm_min(lim ->> 1)) then
        acc := acc + k.v; pick := k.key;
        exit when u < acc;
      end if;
    end loop;
    out := out || pick;
  end loop;
  return out;
end;
$$;

-- garante a agenda de um dia (sorteio criptográfico na 1ª vez, depois fica guardada); o evento nunca repete o da noite anterior
create or replace function public.weather_day_ensure(p_offset int, p_day date, p_depth int default 0)
returns public.weather_days language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.weather_days; prev text; ev jsonb := public.config_get('weather') -> 'night_event'; opts jsonb; n int; st int; steps int;
begin
  select * into r from public.weather_days where offset_min = p_offset and day = p_day;
  if found then return r; end if;
  if p_depth = 0 then prev := (public.weather_day_ensure(p_offset, p_day - 1, 1)).event_id;
  else prev := (select event_id from public.weather_days where offset_min = p_offset and day = p_day - 1); end if;
  select jsonb_agg(x) into opts from jsonb_array_elements(ev -> 'events') x where x ->> 'id' is distinct from prev;
  n := jsonb_array_length(opts);
  steps := (public.hm_min(ev ->> 'start_latest') - public.hm_min(ev -> 'window' ->> 0)) / (ev ->> 'step_minutes')::int + 1;
  st := public.hm_min(ev -> 'window' ->> 0) + floor(public.rand01() * steps)::int * (ev ->> 'step_minutes')::int;
  insert into public.weather_days (offset_min, day, blocks, event_id, event_start_min)
    values (p_offset, p_day, public.weather_gen_blocks(), opts -> floor(public.rand01() * n)::int ->> 'id', st)
    on conflict do nothing;
  select * into r from public.weather_days where offset_min = p_offset and day = p_day;
  return r;
end;
$$;

-- agenda dos dias que o passo de tempo vai cruzar (fuso atual e o fuso novo, se houver troca marcada)
create or replace function public.weather_ensure(p_user uuid, p_from timestamptz, p_to timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare tz text; d date; d1 date; f timestamptz := greatest(p_from, p_to - interval '2 days');
begin
  for tz in select distinct x from unnest(array[public.user_tz(p_user, f), public.user_tz(p_user, p_to + interval '1 day')]) x where x is not null loop
    d := (f at time zone tz)::date - 1; d1 := (p_to at time zone tz)::date + 1;
    while d <= d1 loop perform public.weather_day_ensure(public.tz_offset_min(tz, d), d); d := d + 1; end loop;
  end loop;
end;
$$;

-- ---------- clima num instante (sem habilidades; o team_fx soma Botânica e tetos) ----------
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

-- o que o jogador vê: clima de agora, previsão (1 h, +1 h por ponto da Botânica até 6 h) e o evento a partir do aviso
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

-- Lua Cheia: +40% no ouro das vendas que chegam no evento, até R ÷ 24 por evento
create or replace function public.moon_bonus(p_user uuid, p_amount numeric, fx jsonb)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare
  m numeric := coalesce((fx ->> 'moon')::numeric, 0); st timestamptz; cap numeric; paid numeric; prev timestamptz; lvl int; b numeric;
  ratio numeric := (select (x ->> 'cap_R_ratio')::numeric from jsonb_array_elements(public.config_get('weather') -> 'night_event' -> 'events') x where x ->> 'id' = 'lua_cheia');
begin
  if m <= 0 or coalesce(p_amount, 0) <= 0 then return 0; end if;
  st := (fx -> 'weather' -> 'event' ->> 'start')::timestamptz;
  select moon_start, moon_paid, level into prev, paid, lvl from public.farms where user_id = p_user for update;
  if prev is distinct from st then paid := 0; end if;
  cap := public.ref_income(lvl) * ratio;
  b := round(greatest(0, least(p_amount * m, cap - paid)), 2);
  update public.farms set moon_start = st, moon_paid = paid + b where user_id = p_user;
  return b;
end;
$$;

-- ---------- troca de fuso ----------
-- 1ª vez (vindo do aparelho): vale na hora. Depois: 1 troca a cada 30 dias, valendo na próxima meia-noite.
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

-- ---------- painel ----------
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

-- forçar (ou cancelar, com p_event null) o evento de um dia num fuso; vale para todos daquele fuso; fica no registro
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

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.weather_gen_blocks()', 'public.weather_day_ensure(int, date, int)', 'public.weather_ensure(uuid, timestamptz, timestamptz)',
    'public.weather_now(uuid, timestamptz)', 'public.weather_view(uuid, jsonb)', 'public.moon_bonus(uuid, numeric, jsonb)',
    'public.user_tz(uuid, timestamptz)', 'public.user_day(uuid, timestamptz)', 'public.tz_offset_min(text, date)',
    'public.local_instant(text, date, int)', 'public.hm_min(text)', 'public.fx_at()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array['public.set_timezone(text)', 'public.admin_weather(text, date)', 'public.admin_force_event(text, date, text, text, text)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;

-- ---------- funções que mudam na fase 6 ----------
create or replace function public.team_fx(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := public.config_get('characters');
  fe jsonb := cfg -> 'field_effects';
  crops jsonb := public.config_get('crops') -> 'rules';
  base_stall double precision := coalesce((public.config_get('expeditions') ->> 'stall_price_ratio')::double precision, 0.7);
  v_effects text[] := array['crop_growth_pct', 'growth_all_pct', 'orchard_speed_pct', 'tree_initial_time_pct', 'double_harvest_crop_pct',
    'golden_pct', 'harvest_xp_pct', 'seed_cost_pct', 'shop_discount_pct', 'cleanup_time_pct', 'tool_cost_pct', 'team_capacity_pct',
    'tool_effect_pct', 'stall_price_pts', 'daily_boosted_sale', 'sales_gold_pct', 'recurring_production_pct', 'account_xp_pct',
    'orchard_extra_fruit_chance', 'early_unlock_levels', 'animal_production_pct', 'feed_cost_pct', 'animal_double_pct',
    'expansion_cost_pct', 'vehicle_wear_pct', 'expedition_success_pts', 'expedition_duration_pct', 'route_demand_preview',
    'weather_effect_pct', 'weather_forecast_hours', 'night_event_pct'];
  caps jsonb := coalesce(public.config_get('cards') -> 'bonus_caps', '{}'::jsonb);
  cap_seed double precision := coalesce((caps -> 'seed_sapling_feed_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100;
  ranch boolean := false;
  s jsonb := '{}'::jsonb;
  e text; c record; v double precision;
  com int := -1; ger int := -1; bot boolean := false; bot_choice text;
  pet jsonb := public.pet_info(p_user);
  pet_rare double precision := 0; gato double precision := 0; papagaio double precision := 0; gato_animal double precision := 0;
  v_res jsonb; v_w jsonb := public.weather_now(p_user, public.fx_at()); wcfg jsonb := public.config_get('weather');
  wm double precision; em double precision; cw jsonb; ew jsonb; v_base double precision; v_room double precision; v_cg double precision;
  v_go double precision; v_xp double precision; v_cxp double precision; v_sales double precision; v_warn int;
  dog_pts double precision := 0; dog_rec double precision := 0; it_double double precision := 0; it_animal double precision := 0;
begin
  foreach e in array v_effects loop s := s || jsonb_build_object(e, 0); end loop;
  for c in select ch.class_id, ch.skills, ch.skill_choice, t.material from public.characters ch
           left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
           where ch.user_id = p_user and public.char_active(ch) loop
    foreach e in array v_effects loop
      v := public.skill_effect(c.class_id, c.skills, e);
      if v <> 0 then s := jsonb_set(s, array[e], to_jsonb((s ->> e)::double precision + v)); end if;
    end loop;
    if c.class_id = 'comerciante' then com := public.material_idx(c.material); end if;
    if c.class_id = 'gerente' then ger := public.material_idx(c.material); end if;
    if c.class_id = 'botanica' then bot := true; bot_choice := c.skill_choice; end if;
    if c.class_id = 'rancheira' then ranch := true; end if;
  end loop;
  if pet is not null then
    if (pet ->> 'level')::int >= 5 then pet_rare := (cfg -> 'pets' ->> 'level5_rare_seed_pts')::double precision / 100; end if;
    if pet ->> 'id' = 'gato' then
      gato := (select (x ->> 'energy_recovery_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
      gato_animal := (select (x ->> 'animal_production_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'gato') / 100 * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'cachorro' then
      dog_pts := (select (x ->> 'expedition_success_pts')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'cachorro') * (pet ->> 'factor')::double precision;
      dog_rec := (select (x ->> 'lost_cargo_recovery_chance')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'cachorro') * (pet ->> 'factor')::double precision;
    end if;
    if pet ->> 'id' = 'papagaio' then
      papagaio := (select (x ->> 'sales_gold_pct')::double precision from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio') / 100 * (pet ->> 'factor')::double precision;
    end if;
  end if;
  -- amuletos de quem está em campo: Trevo (colheita dupla) e Pena (produção animal)
  select coalesce(sum(public.item_effect(ch, 'double_harvest_chance_pct')), 0) / 100, coalesce(sum(public.item_effect(ch, 'animal_production_pct')), 0) / 100
    into it_double, it_animal from public.characters ch where ch.user_id = p_user and public.char_active(ch);
  v_res := jsonb_build_object(
    'growth_crop', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'crop_growth_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'growth_orchard', least(coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100,
                   ((s ->> 'orchard_speed_pct')::double precision + (s ->> 'growth_all_pct')::double precision) / 100),
    'tree_initial', (s ->> 'tree_initial_time_pct')::double precision / 100,
    'double_crop', least(coalesce((caps -> 'double_harvest_chance_pct' ->> 'permanent')::double precision, 25) / 100, (s ->> 'double_harvest_crop_pct')::double precision / 100 + it_double),
    'golden', least((crops -> 'golden_harvest' ->> 'cap_permanent')::double precision, (s ->> 'golden_pct')::double precision / 100),
    'golden_mult', (crops -> 'golden_harvest' ->> 'multiplier')::double precision,
    'harvest_xp', ((s ->> 'harvest_xp_pct')::double precision + case when bot then (fe -> 'botanica' ->> 'harvest_xp_pct')::double precision else 0 end) / 100,
    'account_xp', least(coalesce((caps -> 'account_xp_pct' ->> 'permanent')::double precision, 100) / 100, (s ->> 'account_xp_pct')::double precision / 100),
    'recurring', (s ->> 'recurring_production_pct')::double precision / 100,
    'extra_fruit', (s ->> 'orchard_extra_fruit_chance')::double precision,
    'seed_discount', least(cap_seed, (-(s ->> 'seed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'seed_discount_pct_per_material')::double precision * (com + 1) else 0 end) / 100),
    'shop_discount', least(cap_seed, -(s ->> 'shop_discount_pct')::double precision / 100),
    'feed_discount', least(cap_seed, (-(s ->> 'feed_cost_pct')::double precision - (s ->> 'shop_discount_pct')::double precision) / 100),
    'animal_production', ((s ->> 'animal_production_pct')::double precision) / 100 + gato_animal + it_animal,
    'animal_cap', coalesce((caps -> 'animal_production_pct' ->> 'permanent')::double precision, 60) / 100,
    'animal_double', (s ->> 'animal_double_pct')::double precision / 100,
    'expansion_cost', (s ->> 'expansion_cost_pct')::double precision / 100,
    'rancheira', ranch,
    'stall_ratio', least((fe -> 'comerciante' ->> 'stall_price_cap')::double precision,
                   base_stall + ((s ->> 'stall_price_pts')::double precision
                     + case when com >= 0 then (fe -> 'comerciante' ->> 'stall_price_pts_per_material')::double precision * (com + 1) else 0 end) / 100),
    'sales_gold', least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100, (s ->> 'sales_gold_pct')::double precision / 100 + papagaio),
    'daily_boost', (s ->> 'daily_boosted_sale')::double precision,
    'cleanup', (s ->> 'cleanup_time_pct')::double precision / 100,
    'tool_cost', (s ->> 'tool_cost_pct')::double precision / 100,
    'team_capacity', (s ->> 'team_capacity_pct')::double precision / 100,
    'tool_effect', (s ->> 'tool_effect_pct')::double precision / 100,
    'gerente_cut', case when ger >= 0 then ((fe -> 'gerente' ->> 'team_energy_use_pct_base')::double precision
                     + (fe -> 'gerente' ->> 'team_energy_use_pct_per_material')::double precision * ger) / 100 else 0 end,
    'auto_sell', com >= 0,
    'auto_pay', ger >= 0,
    'rare_seed', case when bot then (fe -> 'botanica' ->> 'rare_seed_chance')::double precision else 0 end + pet_rare,
    'seed_refund', case when bot then (fe -> 'botanica' ->> 'seed_refund_chance')::double precision else 0 end,
    'early_unlock', case when (s ->> 'early_unlock_levels')::double precision > 0 and bot_choice is not null
                     then jsonb_build_object('crop', bot_choice, 'levels', (s ->> 'early_unlock_levels')::int) end,
    'gato_rest', gato,
    'exp_success', (s ->> 'expedition_success_pts')::double precision + dog_pts,
    'exp_duration', (s ->> 'expedition_duration_pct')::double precision / 100,
    'vehicle_wear', (s ->> 'vehicle_wear_pct')::double precision / 100,
    'route_preview', (s ->> 'route_demand_preview')::double precision,
    'dog_recover', dog_rec,
    'pet', pet);

  -- clima (bônus permanente, com a Botânica +8% por ponto) e evento noturno (teto absoluto; Botânica mestre +15%)
  wm := 1 + (s ->> 'weather_effect_pct')::double precision / 100;
  em := 1 + (s ->> 'night_event_pct')::double precision / 100;
  cw := v_w -> 'cond_fx'; ew := coalesce(nullif(v_w -> 'event', 'null'::jsonb), '{}');
  -- crescimento: o que já vale no plantio (habilidades) ocupa o teto; o clima entra no que sobra do permanente, o evento no absoluto
  v_base := (v_res ->> 'growth_crop')::double precision;
  v_cg := least((cw ->> 'growth')::double precision * wm, greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100 - v_base));
  v_res := v_res || jsonb_build_object('w_growth', v_cg + least(coalesce((ew ->> 'growth')::double precision, 0) * em,
    greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'absolute')::double precision, 150) / 100 - v_base - v_cg)));
  v_base := (v_res ->> 'growth_orchard')::double precision;
  v_go := least((cw ->> 'growth')::double precision * wm, greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'permanent')::double precision, 100) / 100 - v_base));
  v_res := v_res || jsonb_build_object('w_growth_orchard', v_go + least(coalesce((ew ->> 'growth')::double precision, 0) * em,
    greatest(0, coalesce((caps -> 'growth_speed_pct' ->> 'absolute')::double precision, 150) / 100 - v_base - v_go)));
  -- XP da conta
  v_xp := least(coalesce((caps -> 'account_xp_pct' ->> 'permanent')::double precision, 100) / 100,
                (s ->> 'account_xp_pct')::double precision / 100 + (cw ->> 'account_xp')::double precision * wm);
  v_xp := least(coalesce((caps -> 'account_xp_pct' ->> 'absolute')::double precision, 200) / 100, v_xp + coalesce((ew ->> 'account_xp')::double precision, 0) * em);
  v_cxp := (cw ->> 'char_xp')::double precision * wm + coalesce((ew ->> 'char_xp')::double precision, 0) * em;
  v_sales := least(coalesce((caps -> 'sales_gold_pct' ->> 'permanent')::double precision, 50) / 100,
                   (v_res ->> 'sales_gold')::double precision + (cw ->> 'sales')::double precision * wm);
  v_warn := (wcfg -> 'night_event' ->> 'warning_minutes')::int;
  if pet ->> 'id' = 'papagaio' then
    v_warn := coalesce((select (x ->> 'night_event_warning_minutes')::int from jsonb_array_elements(cfg -> 'pets' -> 'list') x where x ->> 'id' = 'papagaio'), v_warn);
  end if;
  return v_res || jsonb_build_object(
    'w_account_xp', v_xp - (v_res ->> 'account_xp')::double precision,
    'w_sales', v_sales - (v_res ->> 'sales_gold')::double precision,
    'account_xp', v_xp, 'sales_gold', v_sales, 'char_xp', v_cxp,
    'moon', coalesce((ew ->> 'moon')::double precision, 0) * em,
    'forecast_h', least((wcfg -> 'forecast' ->> 'max_hours')::double precision,
                        (wcfg -> 'forecast' ->> 'base_hours')::double precision + (s ->> 'weather_forecast_hours')::double precision),
    'warn_min', v_warn,
    'weather', v_w);
end;
$function$;

create or replace function public.tick_team(p_user uuid, p_hours double precision, p_frac double precision, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := public.config_get('characters');
  dr jsonb := public.config_get('tools_and_items') -> 'tool_durability_rules';
  snacks jsonb := public.config_get('tools_and_items') -> 'snack_cards';
  c public.characters; en jsonb; v_e double precision; v_h double precision; v_lvl int; v_park boolean; v_qty int; v_rev date;
  v_today date := public.game_day(now()); s jsonb; worked double precision;
begin
  for c in select * from public.characters where user_id = p_user for update loop
    en := public.char_energy(c, fx);
    v_e := c.energy; v_h := c.work_hours; v_lvl := c.level; v_park := c.parked; v_qty := c.snack_qty; v_rev := c.revive_day;
    if c.leading_id is not null then
      null; -- conduzindo uma expedição: nem trabalha nem descansa
    elsif c.slot = 'field' and not c.parked and public.char_active(c) and c.energy > 0 then
      worked := p_hours * p_frac;
      v_e := v_e - (en ->> 'use')::double precision * worked;
      v_h := v_h + worked * (1 + public.item_effect(c, 'character_xp_pct') / 100 + coalesce((fx ->> 'char_xp')::double precision, 0)); -- Relógio de Bolso + neblina
      update public.tools set durability = greatest(0, durability - (dr ->> 'loss_per_work_hour')::double precision * worked)
        where user_id = p_user and class_id = c.class_id;
      if v_e <= 0 then
        v_e := 0;
        if public.skill_effect(c.class_id, c.skills, 'daily_revive_energy') > 0 and v_rev is distinct from v_today then
          v_e := public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'); v_rev := v_today;
        else
          v_park := true;
        end if;
      end if;
    else
      v_e := least((en ->> 'max')::double precision, v_e + (en ->> 'rest')::double precision * p_hours);
      if v_park and v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
    end if;
    -- lanche automático abaixo de 15% da energia máxima
    if v_qty > 0 and c.snack_id is not null then
      s := (select x from jsonb_array_elements(snacks) x where x ->> 'id' = c.snack_id);
      while v_qty > 0 and v_e < (s ->> 'auto_trigger_below_energy_pct')::double precision / 100 * (en ->> 'max')::double precision loop
        v_e := least((en ->> 'max')::double precision, v_e + (s ->> 'energy_restore')::double precision);
        v_qty := v_qty - 1;
        if v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
      end loop;
    end if;
    -- nível do personagem: (10 + 1,5 × nível) horas para o próximo
    while v_lvl < (cfg -> 'character_level' ->> 'max')::int
      and v_h >= (cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl loop
      v_h := v_h - ((cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl);
      v_lvl := v_lvl + 1;
    end loop;
    if v_lvl = (cfg -> 'character_level' ->> 'max')::int then v_h := 0; end if;
    update public.characters set energy = v_e, work_hours = v_h, level = v_lvl, parked = v_park, snack_qty = v_qty,
        snack_id = case when v_qty = 0 then null else snack_id end, revive_day = v_rev
      where user_id = p_user and class_id = c.class_id;
  end loop;
end;
$function$;

create or replace function public.exp_chance(p_user uuid, v vehicles, p_route text, p_lead jsonb, p_minigame text, fx jsonb)
 RETURNS double precision
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with e as (select public.config_get('expeditions') c)
  select greatest(0, least((c ->> 'success_cap')::double precision,
    (public.exp_route(p_route) ->> 'success')::double precision
    + ((public.vehicle_def(v.vehicle_id) ->> 'safety_pts')::double precision * public.rarity_mult(v.rarity)
       + coalesce((c -> 'minigame' -> 'result_pts' ->> p_minigame)::double precision, 0)
       + coalesce((p_lead ->> 'success_pts')::double precision, 0)
       + coalesce((fx ->> 'exp_success')::double precision, 0)
       + case fx -> 'weather' ->> 'cond'
           when 'rain' then case when v.vehicle_id = 'carroca' then (c -> 'weather_success_pts' ->> 'cart_in_rain')::double precision
                                 else (c -> 'weather_success_pts' ->> 'rain')::double precision end
           when 'fog' then (c -> 'weather_success_pts' ->> 'fog')::double precision else 0 end
       + case when fx -> 'weather' ->> 'part' = 'night' then (c -> 'weather_success_pts' ->> 'night')::double precision else 0 end
       + case when v.durability < (c ->> 'low_wear_threshold_pct')::double precision then (c ->> 'low_wear_success_pts')::double precision else 0 end
       + case when (select exp_fail_streak from public.farms where user_id = p_user) >= (c -> 'bad_luck_protection' ->> 'after_failures')::int
              then (c -> 'bad_luck_protection' ->> 'bonus_pts')::double precision else 0 end) / 100))
  from e
$function$;

create or replace function public.process_expeditions(p_user uuid, p_t double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; v public.vehicles; fx jsonb; lead jsonb; v_cargo jsonb; v_cap int; v_left int; c record; v_take int;
  v_gold numeric; i int := 0;
begin
  perform public.demand_ensure(public.game_day(now()));
  perform public.demand_ensure(public.game_day(now()) + 1);
  update public.vehicles set rarity = refurb_rarity, refurb_rarity = null, refurb_until = null
    where user_id = p_user and refurb_until is not null and refurb_until <= p_t;
  if not exists (select 1 from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t) then return; end if;
  loop
    i := i + 1; exit when i > 200;
    select * into x from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t order by returns_at, id limit 1;
    exit when not found;
    -- o clima, a noite e a Lua Cheia valem pela hora real em que o veículo volta
    perform set_config('vif.at', (select (fa.synced_at + make_interval(secs => x.returns_at - fa.farm_time))::text from public.farms fa where fa.user_id = p_user), true);
    fx := public.team_fx(p_user);
    perform public.exp_resolve(x.id, fx);
    if x.repeat_left > 0 then
      -- repetição: mesmos produtos da viagem, até a capacidade, com o que houver no Silo
      select * into v from public.vehicles where user_id = p_user and vehicle_id = x.vehicle_id;
      lead := case when x.led then public.lead_info(p_user) else null end;
      v_cap := public.exp_capacity(v, lead); v_left := v_cap; v_cargo := '{}';
      for c in select key, value::int q from jsonb_each_text(x.cargo) order by value::int desc, key loop
        select least(coalesce(max(qty), 0), v_left) into v_take from public.silo where user_id = p_user and item_id = c.key;
        if v_take > 0 then v_cargo := v_cargo || jsonb_build_object(c.key, v_take); v_left := v_left - v_take; end if;
      end loop;
      if v_cargo <> '{}'::jsonb then
        perform public.exp_take_cargo(p_user, v_cargo);
        select gold into v_gold from public.wallets where user_id = p_user;
        perform public.exp_depart(p_user, x.convoy_id, v, x.route_id, v_cargo, x.insurance > 0, lead, x.minigame, x.returns_at,
          x.seq + 1, x.repeat_left - 1, fx, v_gold);
      end if;
    end if;
    -- o Gerente volta quando nenhum veículo que ele conduz está viajando
    if x.led and not exists (select 1 from public.expeditions where user_id = p_user and convoy_id = x.convoy_id and led and status = 'travel') then
      update public.characters set leading_id = null where user_id = p_user and class_id = 'gerente' and leading_id = x.convoy_id;
    end if;
  end loop;
  perform set_config('vif.at', '', true);
end;
$function$;

create or replace function public.exp_resolve(p_id uuid, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; e jsonb := public.config_get('expeditions'); r jsonb; lead jsonb; u double precision; pc double precision;
  v_out text; v_gold numeric := 0; v_refund numeric := 0; v_loss double precision; v_back jsonb := '{}'; v_drops jsonb := '[]';
  v_rolls int := 1; k int; c record; v_lost int; v_rec boolean := false; v_txt text; v_items jsonb;
begin
  select * into x from public.expeditions where id = p_id for update;
  r := public.exp_route(x.route_id);
  if x.led then lead := public.lead_info(x.user_id); end if;
  u := public.rand01();
  pc := least(x.chance, (e -> 'crit' ->> 'chance')::double precision + coalesce((lead ->> 'crit_pts')::double precision, 0) / 100);
  if u < pc then v_out := 'crit'; elsif u < x.chance then v_out := 'success'; else v_out := 'fail'; end if;

  if v_out = 'crit' then
    v_gold := round(x.cargo_value * (1 + (e -> 'crit' ->> 'bonus_value')::numeric) * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
    v_rolls := (e -> 'crit' ->> 'item_rolls')::int;
  elsif v_out = 'success' then
    v_gold := round(x.cargo_value * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
  else
    v_loss := ((r -> 'loss' ->> 0)::double precision + public.rand01() * ((r -> 'loss' ->> 1)::double precision - (r -> 'loss' ->> 0)::double precision))
              * (1 + coalesce((lead ->> 'loss_pct')::double precision, 0) / 100);
    v_loss := greatest(0, least(1, v_loss));
    -- o Cachorro pode farejar a carga perdida
    if public.rand01() < coalesce((fx ->> 'dog_recover')::double precision, 0) then v_rec := true; v_loss := 0; end if;
    for c in select key, value::int q from jsonb_each_text(x.cargo) loop
      v_lost := round(c.q * v_loss)::int;
      v_back := v_back || jsonb_build_object(c.key, c.q - v_lost);
    end loop;
    if x.insurance > 0 then
      v_refund := round(greatest(0, v_loss - (e ->> 'insurance_deductible')::double precision)::numeric * x.cargo_value, 2);
    end if;
  end if;

  if v_gold > 0 then v_gold := v_gold + public.moon_bonus(x.user_id, v_gold, fx); end if;

  -- prêmios: item (vestimenta ou amuleto), Escritura e Kit de Reforma
  v_items := (public.config_get('tools_and_items') -> 'clothing_cards') || (public.config_get('tools_and_items') -> 'amulet_cards');
  for k in 1 .. v_rolls loop
    if public.rand01() < (r ->> 'item_chance')::double precision * (1 + coalesce((lead ->> 'item_pct')::double precision, 0) / 100) then
      v_drops := v_drops || to_jsonb((v_items -> floor(public.rand01() * jsonb_array_length(v_items))::int ->> 'id') || ':' || public.pick_rarity(r -> 'item_rarity'));
    end if;
  end loop;
  if public.rand01() < (r ->> 'deed_chance')::double precision * (1 + coalesce((lead ->> 'deed_pct')::double precision, 0) / 100) then
    v_drops := v_drops || to_jsonb('deed'::text);
  end if;
  if public.rand01() < (r ->> 'kit_chance')::double precision then
    v_drops := v_drops || to_jsonb('kit:' || public.pick_rarity(r -> 'kit_rarity'));
  end if;

  v_txt := (e -> 'reports' -> v_out) ->> floor(public.rand01() * jsonb_array_length(e -> 'reports' -> v_out))::int;
  v_txt := replace(replace(v_txt, '{route}', r ->> 'name_pt'), '{lost}', round(coalesce(v_loss, 0) * 100)::text || '%');
  if v_rec then v_txt := v_txt || ' ' || (e -> 'reports' ->> 'recovered'); end if;

  update public.expeditions set status = 'back', outcome = v_out, loss_frac = v_loss, gold = v_gold, refund = v_refund,
      cargo_back = v_back, drops = v_drops, report = v_txt
    where id = p_id;
  update public.farms set exp_fail_streak = case when v_out = 'fail' then exp_fail_streak + 1 else 0 end where user_id = x.user_id;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (x.user_id, 'expedition.back', x.user_id, jsonb_build_object('id', x.id, 'route', x.route_id, 'vehicle', x.vehicle_id,
      'outcome', v_out, 'chance', round(x.chance::numeric, 4), 'roll', round(u::numeric, 6), 'gold', v_gold, 'refund', v_refund, 'drops', v_drops));
end;
$function$;

create or replace function public.sell_at_stall(p_item text, p_qty integer, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid(); v_moon numeric := 0;
  fx jsonb; v_price numeric; v_have int; v_amount numeric; v_time double precision; v_boost numeric := 1; v_day date := public.game_day(now());
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'chave de idempotência obrigatória' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.ledger where user_id = v_user and idempotency_key = p_idempotency_key) then
    return public.farm_state(v_user);
  end if;
  v_price := public.item_price(p_item);
  if v_price is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
  if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  fx := public.team_fx(v_user);
  if (fx ->> 'daily_boost')::numeric > 1 and (select boosted_sale_day from public.farms where user_id = v_user) is distinct from v_day then
    v_boost := (fx ->> 'daily_boost')::numeric;
    update public.farms set boosted_sale_day = v_day where user_id = v_user;
  end if;
  update public.silo set qty = qty - p_qty where user_id = v_user and item_id = p_item;
  v_amount := round(p_qty * v_price * (fx ->> 'stall_ratio')::numeric * (1 + (fx ->> 'sales_gold')::numeric) * v_boost, 2);
  v_moon := public.moon_bonus(v_user, v_amount, fx);
  v_amount := v_amount + v_moon;
  perform public.ledger_post(v_user, v_amount, 'stall_sale', jsonb_build_object('item', p_item, 'qty', p_qty, 'price', v_price,
    'ratio', fx -> 'stall_ratio', 'sales_gold', fx -> 'sales_gold', 'boost', v_boost, 'moon', v_moon), p_idempotency_key);
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots set stalled_reason = null, free_since = v_time where user_id = v_user and stalled_reason = 'sem_ouro';
  perform public.advance_farm(v_user, now());
  perform public.feed_hungry_now(v_user);
  return public.farm_state(v_user);
end;
$function$;

create or replace function public.auto_sell(p_user uuid, fx jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_total numeric := 0; v_moon numeric := 0; v_items jsonb := '{}'::jsonb; v_price numeric;
begin
  if not coalesce((fx ->> 'auto_sell')::boolean, false) then return 0; end if;
  for r in select item_id, qty from public.silo where user_id = p_user and auto_sell and qty > 0 for update loop
    v_price := public.item_price(r.item_id);
    if v_price is null then continue; end if;
    v_total := v_total + r.qty * v_price * (fx ->> 'stall_ratio')::numeric * (1 + (fx ->> 'sales_gold')::numeric);
    v_items := v_items || jsonb_build_object(r.item_id, r.qty);
    update public.silo set qty = 0 where user_id = p_user and item_id = r.item_id;
  end loop;
  v_total := round(v_total, 2);
  if v_total > 0 then
    v_moon := public.moon_bonus(p_user, v_total, fx);
    v_total := v_total + v_moon;
    perform public.ledger_post(p_user, v_total, 'auto_sale', jsonb_build_object('items', v_items, 'ratio', fx -> 'stall_ratio', 'moon', v_moon));
  end if;
  return v_total;
end;
$function$;

create or replace function public.process_payday(p_user uuid, p_until timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_last date; v_today date := public.user_day(p_user, p_until); v_gold numeric; v_sal numeric; c public.characters;
begin
  select coalesce(last_payday, v_today) into v_last from public.farms where user_id = p_user for update;
  while v_last < v_today loop
    v_last := v_last + 1;
    for c in select * from public.characters where user_id = p_user and class_id <> 'agricultor' order by hired_at loop
      v_sal := public.salary_of(p_user, c);
      if v_sal <= 0 then continue; end if;
      select gold into v_gold from public.wallets where user_id = p_user;
      if c.debt = 0 and v_gold >= v_sal then
        perform public.ledger_post(p_user, -v_sal, 'salary', jsonb_build_object('class', c.class_id, 'day', v_last), 'salary:' || c.class_id || ':' || v_last);
      else
        update public.characters set debt = debt + v_sal, unpaid_days = unpaid_days + 1 where user_id = p_user and class_id = c.class_id;
      end if;
    end loop;
  end loop;
  update public.farms set last_payday = v_last where user_id = p_user;
end;
$function$;

create or replace function public.advance_farm(p_user uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.farms;
  v_farm jsonb := public.config_get('farm');
  v_work jsonb := public.config_get('crops') -> 'rules' -> 'work_units';
  v_plant_cost double precision := coalesce((v_work ->> 'plant')::double precision, 0.5);
  v_harvest_cost double precision := coalesce((v_work ->> 'harvest')::double precision, 0.5);
  v_step double precision := coalesce((public.config_get('characters') ->> 'step_minutes')::double precision, 10) * 60;
  v_cap_h double precision := coalesce((v_farm ->> 'labor_bank_cap_hours')::double precision, 1);
  v_end timestamptz;
  t0 double precision; t1 double precision; seg0 double precision; seg1 double precision;
  t_cur double precision; labor double precision; labor0 double precision; used double precision;
  rate double precision; cap double precision; fx jsonb; tr jsonb;
  v_gold numeric; v_seed_spent numeric; v_refund numeric; v_plantings int; v_seed numeric; v_feed numeric; v_f numeric;
  e record; lt double precision; te double precision; v_real timestamptz; v_w jsonb; v_g double precision; v_cut double precision;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  labor := f.labor_bank;
  seg0 := t0;
  perform public.weather_ensure(p_user, f.synced_at, p_now);
  -- a troca de fuso marcada vale a partir da meia-noite combinada
  update public.profiles set timezone = tz_pending, tz_pending = null, tz_pending_at = null
    where id = p_user and tz_pending is not null and tz_pending_at <= f.synced_at;

  while seg0 < t1 loop
    -- relógio real do passo: o clima e o evento valem pela hora local do jogador
    v_real := f.synced_at + make_interval(secs => seg0 - t0);
    perform set_config('vif.at', v_real::text, true);
    v_w := public.weather_now(p_user, v_real);
    v_cut := extract(epoch from ((v_w ->> 'next')::timestamptz - v_real));
    seg1 := least(t1, seg0 + v_step, seg0 + greatest(1, coalesce(v_cut, v_step)));
    -- evento que valeu para a conta (no máximo 1 a cada 20 h, mesmo trocando de fuso)
    if coalesce((v_w -> 'event' ->> 'active')::boolean, false) then
      update public.farms set last_event_start = (v_w -> 'event' ->> 'start')::timestamptz
        where user_id = p_user and last_event_start is distinct from (v_w -> 'event' ->> 'start')::timestamptz;
    end if;
    -- salário das meias-noites até o fim deste passo (no relógio real)
    perform public.process_payday(p_user, f.synced_at + make_interval(secs => seg1 - t0));
    fx := public.team_fx(p_user);
    if (fx ->> 'auto_pay')::boolean then perform public.pay_debts(p_user); end if;
    perform public.rotate_team(p_user);
    fx := public.team_fx(p_user);
    tr := public.team_rate(p_user, fx);
    -- Sol forte e Calor Dourado: quem está crescendo anda mais rápido neste passo (lavoura e pomar)
    v_g := coalesce((fx ->> 'w_growth')::double precision, 0);
    if v_g > 0 then
      update public.plots set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                              else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and state = 'growing' and ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_growth_orchard')::double precision, 0);
    if v_g > 0 then
      update public.trees set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                              else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and fruit_id is not null and ready_at > seg0;
    end if;
    rate := (tr ->> 'working')::double precision / 3600.0;
    cap := (tr ->> 'nominal')::double precision * v_cap_h;
    if cap > 0 then labor := least(labor, cap); end if; -- teto do trabalho guardado (ninguém em campo: guarda o que tinha)
    cap := greatest(cap, labor);
    labor0 := labor; used := 0; t_cur := seg0;
    select gold into v_gold from public.wallets where user_id = p_user;
    v_seed_spent := 0; v_refund := 0; v_plantings := 0;
    -- animais com fome voltam a produzir quando há ouro para a ração (sem gastar trabalho)
    v_feed := public.animals_feed_hungry(p_user, seg0, fx, v_gold);

    loop
      i := i + 1;
      exit when i > 20000; -- trava de segurança
      select * into e from (
        select 'harvest'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, v_harvest_cost as cost
          from public.plots pl
          where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= seg1
        union all
        select 'harvest_tree', t.lot_id, t.slot, t.ready_at, v_harvest_cost
          from public.trees t
          where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= seg1
        union all
        select 'collect', a.house_id, a.slot, a.ready_at, v_harvest_cost
          from public.animals a
          where a.user_id = p_user and a.state = 'growing' and a.ready_at <= seg1
        union all
        select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost
          from public.plots pl join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
          where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null
            and greatest(coalesce(pl.free_since, t0), ol.ready_at) <= seg1
      ) q
      order by avail, key, slot
      limit 1;
      exit when not found;

      -- quando a equipe terá o trabalho necessário
      lt := least(cap, labor + rate * (greatest(e.avail, t_cur) - t_cur));
      if lt >= e.cost then te := greatest(e.avail, t_cur);
      elsif rate > 0 then te := greatest(e.avail, t_cur) + (e.cost - lt) / rate;
      else te := seg1 + 1; end if;
      exit when te > seg1; -- a fila é única: se a primeira tarefa não cabe, nenhuma cabe neste passo

      if e.kind = 'plant' then
        v_seed := public.seed_price((select crop_id from public.plots where user_id = p_user and plot_id = e.key), fx);
        if v_gold - v_seed_spent - v_feed < v_seed then
          update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
          continue;
        end if;
        v_seed_spent := v_seed_spent + public.plant_plot(p_user, e.key, (select crop_id from public.plots where user_id = p_user and plot_id = e.key), te, fx);
        v_plantings := v_plantings + 1;
      elsif e.kind = 'harvest' then
        v_refund := v_refund + public.harvest_plot(p_user, e.key, te, fx);
      elsif e.kind = 'collect' then
        perform public.animal_collect(p_user, e.key, e.slot, te, fx, true);
        v_f := public.animal_start(p_user, e.key, e.slot, te, fx, v_gold - v_seed_spent - v_feed);
        v_feed := v_feed + coalesce(v_f, 0);
      else
        perform public.harvest_tree(p_user, e.key, e.slot, te, fx);
      end if;
      -- se precisou esperar, no instante te o trabalho juntado é exatamente o custo: sobra 0
      -- (corrige a fase 2, que descontava a espera duas vezes e deixava o trabalho fora do jogo mais lento)
      labor := case when lt >= e.cost then lt - e.cost else 0 end;
      used := used + e.cost;
      t_cur := te;
    end loop;

    if seg1 > t_cur then labor := least(cap, labor + rate * (seg1 - t_cur)); end if;
    labor := greatest(0, labor);
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds', jsonb_build_object('plantings', v_plantings, 'farm_time', round(seg1::numeric, 1)));
    end if;
    if v_refund > 0 then
      perform public.ledger_post(p_user, round(v_refund, 2), 'seed_refund', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    if v_feed > 0 then
      perform public.ledger_post(p_user, -round(v_feed, 2), 'feed', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    -- energia, nível e desgaste na fração do passo em que a equipe produziu trabalho
    perform public.tick_team(p_user, (seg1 - seg0) / 3600.0,
      case when rate > 0 then least(1, greatest(0, (labor - labor0 + used) / (rate * (seg1 - seg0)))) else 0 end, fx);
    if public.auto_sell(p_user, fx) > 0 then
      update public.plots set stalled_reason = null, free_since = seg1 where user_id = p_user and stalled_reason = 'sem_ouro';
    end if;
    seg0 := seg1;
  end loop;

  perform set_config('vif.at', '', true);
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
end;
$function$;

create or replace function public.farm_state(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  fx jsonb := public.team_fx(p_user);
  tr jsonb := public.team_rate(p_user, fx);
  v_level int; base jsonb; v_chars jsonb; v_snacks jsonb;
begin
  select level into v_level from public.farms where user_id = p_user;
  select coalesce(jsonb_agg(jsonb_build_object(
      'class_id', ch.class_id, 'slot', ch.slot, 'energy', round(ch.energy::numeric, 2), 'parked', ch.parked,
      'level', ch.level, 'work_hours', round(ch.work_hours::numeric, 3), 'skills', ch.skills, 'skill_choice', ch.skill_choice,
      'reset_week', ch.reset_week, 'debt', ch.debt, 'unpaid_days', ch.unpaid_days, 'snack_id', ch.snack_id, 'snack_qty', ch.snack_qty,
      'cloth_id', ch.cloth_id, 'amulet_id', ch.amulet_id, 'material', coalesce(t.material, 'wood'), 'durability', round(coalesce(t.durability, 100)::numeric, 2),
      'rate', round(public.char_rate(ch, t.material, coalesce(t.durability, 100), fx)::numeric, 3),
      'energy_max', (public.char_energy(ch, fx) ->> 'max')::numeric, 'energy_use', round((public.char_energy(ch, fx) ->> 'use')::numeric, 3),
      'energy_rest', round((public.char_energy(ch, fx) ->> 'rest')::numeric, 3), 'active', public.char_active(ch), 'leading', ch.leading_id is not null,
      'salary', public.salary_of(p_user, ch)) order by ch.hired_at), '[]')
    into v_chars
    from public.characters ch left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
    where ch.user_id = p_user;
  select coalesce(jsonb_object_agg(x ->> 'id', round(public.ref_income(v_level) * (x ->> 'price_R_ratio')::numeric * (1 - (fx ->> 'shop_discount')::numeric), 2)), '{}')
    into v_snacks from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x;
  select jsonb_build_object(
    'server_now', now(),
    'game_day', public.user_day(p_user, now()),
    'weather', public.weather_view(p_user, fx),
    'farm_time', f.farm_time,
    'synced_at', f.synced_at,
    'last_activity_at', f.last_activity_at,
    'offline_cap_hours', (public.config_get('farm') ->> 'offline_cap_hours')::int,
    'labor_bank', f.labor_bank,
    'labor_per_hour', round((tr ->> 'working')::numeric, 3),
    'labor_nominal', round((tr ->> 'nominal')::numeric, 3),
    'labor_cap_hours', (public.config_get('farm') ->> 'labor_bank_cap_hours')::double precision,
    'nickname', pr.nickname,
    'is_admin', pr.is_admin,
    'gold', w.gold,
    'level', f.level,
    'xp', f.xp,
    'xp_to_next', (public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric,
    'last_payday', f.last_payday,
    'boosted_sale_day', f.boosted_sale_day,
    'pet_swapped_at', f.pet_swapped_at,
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', l.lot_id, 'ready_at', l.ready_at, 'purchase_n', l.purchase_n) order by l.lot_id), '[]')
      from public.owned_lots l where l.user_id = p_user),
    'plots', (select coalesce(jsonb_agg(jsonb_build_object(
        'plot_id', pl.plot_id, 'crop_id', pl.crop_id, 'state', pl.state, 'planted_crop_id', pl.planted_crop_id,
        'planted_at', pl.planted_at, 'ready_at', pl.ready_at, 'harvests_done', pl.harvests_done, 'stalled_reason', pl.stalled_reason,
        'rarity', pl.rarity) order by pl.plot_id), '[]')
      from public.plots pl where pl.user_id = p_user),
    'trees', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', t.lot_id, 'slot', t.slot, 'fruit_id', t.fruit_id,
        'planted_at', t.planted_at, 'ready_at', t.ready_at, 'rarity', t.rarity, 'rare_left', t.rare_left) order by t.lot_id, t.slot), '[]')
      from public.trees t where t.user_id = p_user),
    'silo', (select coalesce(jsonb_object_agg(s.item_id, s.qty), '{}') from public.silo s where s.user_id = p_user and s.qty > 0),
    'auto_sell', (select coalesce(jsonb_agg(s.item_id order by s.item_id), '[]') from public.silo s where s.user_id = p_user and s.auto_sell),
    'inventory', (select coalesce(jsonb_object_agg(iv.item_id, iv.qty), '{}') from public.inventory iv where iv.user_id = p_user and iv.qty > 0),
    'tools', (select coalesce(jsonb_object_agg(tl.class_id, tl.material), '{}') from public.tools tl where tl.user_id = p_user),
    'characters', v_chars,
    'animals', (select coalesce(jsonb_agg(jsonb_build_object('house_id', a.house_id, 'slot', a.slot, 'animal_id', a.animal_id, 'rarity', a.rarity,
        'state', a.state, 'cycle_start', a.cycle_start, 'ready_at', a.ready_at) order by a.house_id, a.slot), '[]')
      from public.animals a where a.user_id = p_user),
    'houses', (select jsonb_object_agg(h.key, jsonb_build_object('owned', public.house_ready(p_user, h.key, f.farm_time),
        'tier', coalesce((select ah.tier from public.animal_houses ah where ah.user_id = p_user and ah.house_id = h.key), 0),
        'slots', public.house_slots(p_user, h.key), 'bird_slots', public.house_bird_slots(p_user, h.key, f.farm_time), 'lot', public.house_lot(h.key)))
      from jsonb_each(public.config_get('animals') -> 'houses') h),
    'lake', public.lake_ready(p_user, f.farm_time),
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p.pet_id, 'affinity', p.affinity, 'last_care', p.last_care,
        'active', p.active, 'linked_class', p.linked_class) order by p.adopted_at), '[]') from public.pets p where p.user_id = p_user),
    'pet', fx -> 'pet',
    'snack_prices', v_snacks,
    'fx', jsonb_build_object('stall_ratio', fx -> 'stall_ratio', 'seed_discount', fx -> 'seed_discount', 'sales_gold', fx -> 'sales_gold',
        'shop_discount', fx -> 'shop_discount', 'auto_sell', fx -> 'auto_sell', 'auto_pay', fx -> 'auto_pay', 'rare_seed', fx -> 'rare_seed',
        'seed_refund', fx -> 'seed_refund', 'gerente_cut', fx -> 'gerente_cut', 'early_unlock', fx -> 'early_unlock', 'daily_boost', fx -> 'daily_boost',
        'growth_crop', fx -> 'growth_crop', 'growth_orchard', fx -> 'growth_orchard', 'tree_initial', fx -> 'tree_initial', 'cleanup', fx -> 'cleanup',
        'tool_cost', fx -> 'tool_cost', 'harvest_xp', fx -> 'harvest_xp', 'golden', fx -> 'golden',
        'feed_discount', fx -> 'feed_discount', 'animal_production', fx -> 'animal_production', 'animal_cap', fx -> 'animal_cap',
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira',
        'exp_success', fx -> 'exp_success', 'exp_duration', fx -> 'exp_duration', 'vehicle_wear', fx -> 'vehicle_wear', 'dog_recover', fx -> 'dog_recover',
        'char_xp', fx -> 'char_xp', 'account_xp', fx -> 'account_xp')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base || public.exp_state(p_user);
end;
$function$;
