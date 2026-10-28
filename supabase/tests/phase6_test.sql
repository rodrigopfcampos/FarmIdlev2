-- Testes da fase 6: agenda do clima por fuso, evento noturno (19–21 h locais, sem repetir), bônus do clima e do evento,
-- crescimento acelerado, Lua Cheia com teto, 1 evento a cada 20 h, risco das expedições, troca de fuso e painel.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
-- fase 7: missões desligadas (os prêmios mudariam as contas deste teste)
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid();   -- São Paulo
  b uuid := gen_random_uuid();   -- Tóquio
  adm uuid := gen_random_uuid();
  r public.weather_days; prev public.weather_days; d date; k int; n int; w jsonb; fx jsonb; s jsonb;
  sp text := 'America/Sao_Paulo'; tk text := 'Asia/Tokyo';
  t0 timestamptz; ft double precision; v_ready double precision; v_gold0 numeric; v_gold1 numeric; v_cap numeric; v_m int;
  c_sun double precision; c_rain double precision; v public.vehicles;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f6-a-' || a || '@exemplo.test', '{"nickname":"Fase6 A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f6-b-' || b || '@exemplo.test', '{"nickname":"Fase6 B","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f6-adm-' || adm || '@exemplo.test', '{"nickname":"Fase6 Adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;

  -- 1. agenda sorteada: 8 blocos de 3 h, Sol forte só 09–18, Neblina só 03–12; evento entre 19:00 e 20:15 (passos de 5) e nunca igual à noite anterior
  for k in 0 .. 199 loop
    d := date '2030-01-01' + k;
    r := public.weather_day_ensure(-9999, d);
    if array_length(r.blocks, 1) <> 8 then raise exception 'FALHA 1: % blocos', array_length(r.blocks, 1); end if;
    for n in 1 .. 8 loop
      if r.blocks[n] = 'hot_sun' and n not in (4, 5, 6) then raise exception 'FALHA 2: Sol forte no bloco %', n; end if;
      if r.blocks[n] = 'fog' and n not in (2, 3, 4) then raise exception 'FALHA 3: Neblina no bloco %', n; end if;
    end loop;
    if r.event_start_min < 19 * 60 or r.event_start_min > 20 * 60 + 15 or r.event_start_min % 5 <> 0 then raise exception 'FALHA 4: evento às % min', r.event_start_min; end if;
    if k > 0 and r.event_id = prev.event_id then raise exception 'FALHA 5: evento repetiu em %', d; end if;
    prev := r;
  end loop;
  select count(*) into n from public.weather_days where offset_min = -9999 and blocks[1] = 'sunny';
  if n < 75 or n > 135 then raise exception 'FALHA 6: Ensolarado à meia-noite em % de 200 dias (esperado ~104: 0,40 de 0,77 sem Sol forte e Neblina)', n; end if;

  -- 2. cada conta segue o próprio fuso: o evento das 19:00 locais acontece em instantes diferentes
  update public.profiles set timezone = tk where id = b;
  d := (now() at time zone sp)::date;
  perform public.weather_day_ensure(public.tz_offset_min(sp, d), d);
  perform public.weather_day_ensure(public.tz_offset_min(tk, d), d);
  update public.weather_days set event_id = 'chuva_de_bencaos', event_start_min = 19 * 60, blocks = array_fill('sunny'::text, array[8])
    where (offset_min, day) in ((public.tz_offset_min(sp, d), d), (public.tz_offset_min(tk, d), d));
  w := public.weather_now(a, public.local_instant(sp, d, 19 * 60 + 10));
  if not (w -> 'event' ->> 'active')::boolean or w ->> 'part' <> 'night' then raise exception 'FALHA 7: evento de São Paulo às 19:10 locais %', w; end if;
  w := public.weather_now(b, public.local_instant(sp, d, 19 * 60 + 10));
  if (w -> 'event' ->> 'active')::boolean then raise exception 'FALHA 8: Tóquio teve evento às 19:10 de São Paulo'; end if;
  w := public.weather_now(b, public.local_instant(tk, d, 19 * 60 + 10));
  if not (w -> 'event' ->> 'active')::boolean then raise exception 'FALHA 9: evento de Tóquio às 19:10 de Tóquio %', w; end if;
  if (public.weather_now(a, public.local_instant(sp, d, 19 * 60 + 45)) -> 'event' ->> 'active')::boolean then raise exception 'FALHA 10: evento passou de 45 min'; end if;
  if public.user_day(a, '2030-06-01 13:00+00') = public.user_day(b, '2030-06-01 16:00+00') then raise exception 'FALHA 11: virada do dia não segue o fuso'; end if;

  -- 3. bônus: Chuva +10% XP da conta; Neblina +10% XP da conta e dos personagens; Sol forte +10% crescimento; noite +5% vendas
  update public.weather_days set blocks = array['fog','fog','fog','rain','hot_sun','rain','rain','rain'], event_id = null
    where offset_min = public.tz_offset_min(sp, d) and day = d;
  perform set_config('vif.at', public.local_instant(sp, d, 7 * 60)::text, true);
  fx := public.team_fx(a);
  if abs((fx ->> 'w_account_xp')::numeric - 0.10) > 0.0001 or abs((fx ->> 'char_xp')::numeric - 0.10) > 0.0001 then raise exception 'FALHA 12: neblina %', fx -> 'weather'; end if;
  perform set_config('vif.at', public.local_instant(sp, d, 13 * 60)::text, true);
  fx := public.team_fx(a);
  if abs((fx ->> 'w_growth')::numeric - 0.10) > 0.0001 or (fx ->> 'w_account_xp')::numeric <> 0 then raise exception 'FALHA 13: sol forte %', fx; end if;
  perform set_config('vif.at', public.local_instant(sp, d, 22 * 60)::text, true);
  fx := public.team_fx(a);
  if abs((fx ->> 'w_account_xp')::numeric - 0.10) > 0.0001 or abs((fx ->> 'w_sales')::numeric - 0.05) > 0.0001 then raise exception 'FALHA 14: chuva à noite %', fx; end if;

  -- 4. expedições: chuva −4 pontos, Carroça na chuva −8, noite −2
  select * into v from public.vehicles where user_id = a and vehicle_id = 'carroca';
  perform set_config('vif.at', public.local_instant(sp, d, 13 * 60)::text, true);
  c_sun := public.exp_chance(a, v, 'porto', null, 'done', public.team_fx(a));
  perform set_config('vif.at', public.local_instant(sp, d, 16 * 60)::text, true);
  c_rain := public.exp_chance(a, v, 'porto', null, 'done', public.team_fx(a));
  if abs(c_sun - c_rain - 0.08) > 0.0001 then raise exception 'FALHA 15: Carroça na chuva tirou % (esperado 0,08)', c_sun - c_rain; end if;
  v.vehicle_id := 'carro';
  if abs(c_sun - public.exp_chance(a, v, 'porto', null, 'done', public.team_fx(a)) - 0.04 - (public.vehicle_def('carroca') ->> 'safety_pts')::double precision / 100
         + (public.vehicle_def('carro') ->> 'safety_pts')::double precision / 100) > 0.0001 then raise exception 'FALHA 16: chuva sem Carroça'; end if;
  perform set_config('vif.at', public.local_instant(sp, d, 22 * 60)::text, true);
  v.vehicle_id := 'carroca';
  if abs(c_sun - public.exp_chance(a, v, 'porto', null, 'done', public.team_fx(a)) - 0.10) > 0.0001 then raise exception 'FALHA 17: chuva à noite com Carroça'; end if;
  perform set_config('vif.at', '', true);

  -- 5. Sol forte acelera quem está crescendo: 30 min a +10% adiantam 3 min
  d := (now() at time zone sp)::date - 1;
  perform public.weather_day_ensure(public.tz_offset_min(sp, d), d);
  update public.weather_days set blocks = array_fill('hot_sun'::text, array[8]), event_id = null where offset_min = public.tz_offset_min(sp, d) and day = d;
  t0 := public.local_instant(sp, d, 10 * 60);
  select farm_time into ft from public.farms where user_id = a;
  update public.farms set synced_at = t0, last_activity_at = t0, last_payday = (now() at time zone sp)::date where user_id = a;
  update public.plots set state = 'growing', crop_id = null, planted_crop_id = 'alface', planted_at = ft, ready_at = ft + 3600 where user_id = a and plot_id = 'A1-1';
  perform public.advance_farm(a, t0 + interval '30 minutes');
  select ready_at into v_ready from public.plots where user_id = a and plot_id = 'A1-1';
  if abs(v_ready - (ft + 3600 - 180)) > 0.5 then raise exception 'FALHA 18: pronto em % (esperado %)', v_ready - ft, 3600 - 180; end if;

  -- 6. 1 evento por conta a cada 20 h, mesmo trocando de fuso
  d := (now() at time zone sp)::date + 3;
  perform public.weather_day_ensure(public.tz_offset_min(sp, d), d);
  update public.weather_days set event_id = 'calor_dourado', event_start_min = 19 * 60 where offset_min = public.tz_offset_min(sp, d) and day = d;
  update public.farms set last_event_start = public.local_instant(sp, d, 19 * 60) - interval '10 hours' where user_id = a;
  w := public.weather_now(a, public.local_instant(sp, d, 19 * 60 + 5));
  if (w -> 'event' ->> 'active')::boolean or not (w -> 'event' ->> 'suppressed')::boolean then raise exception 'FALHA 19: 2º evento em 10 h %', w -> 'event'; end if;
  update public.farms set last_event_start = public.local_instant(sp, d, 19 * 60) - interval '21 hours' where user_id = a;
  if not (public.weather_now(a, public.local_instant(sp, d, 19 * 60 + 5)) -> 'event' ->> 'active')::boolean then raise exception 'FALHA 20: evento depois de 21 h'; end if;
  update public.farms set last_event_start = null, synced_at = now(), last_activity_at = now() where user_id = a;

  -- 7. Lua Cheia agora (forçada pelo painel): +40% na venda, até R ÷ 24 por evento
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  d := (now() at time zone sp)::date;
  v_m := (extract(hour from now() at time zone sp)::int * 60 + extract(minute from now() at time zone sp)::int) / 5 * 5;
  if v_m > 24 * 60 - 45 then v_m := 24 * 60 - 45; end if;
  begin perform public.admin_force_event(sp, d, 'lua_cheia', '19:00', 'x'); raise exception 'FALHA 21: forçou sem justificativa';
  exception when check_violation then null; end;
  s := public.admin_force_event(sp, d, 'lua_cheia', lpad((v_m / 60)::text, 2, '0') || ':' || lpad((v_m % 60)::text, 2, '0'), 'teste da Lua Cheia');
  if s -> 'days' -> 1 ->> 'event_id' <> 'lua_cheia' or not (s -> 'days' -> 1 ->> 'forced')::boolean then raise exception 'FALHA 22: painel %', s; end if;
  reset role;
  if not exists (select 1 from public.audit_log where action = 'admin.force_event' and actor_id = adm) then raise exception 'FALHA 23: sem registro'; end if;
  update public.weather_days set blocks = array_fill('sunny'::text, array[8]) where offset_min = public.tz_offset_min(sp, d) and day = d;
  insert into public.silo (user_id, item_id, qty) values (a, 'batata', 100000);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  if s -> 'weather' -> 'event' ->> 'id' <> 'lua_cheia' or not (s -> 'weather' -> 'event' ->> 'active')::boolean then raise exception 'FALHA 24: jogador não vê a Lua Cheia %', s -> 'weather'; end if;
  reset role;
  select (s ->> 'gold')::numeric into v_gold0;
  v_cap := public.ref_income((s ->> 'level')::int) / 24;
  set local role authenticated;
  s := public.sell_at_stall('batata', 1, 'f6-moon-1-' || a);
  reset role;
  select moon_paid into v_gold1 from public.farms where user_id = a;
  if v_gold1 <= 0 or abs(((s ->> 'gold')::numeric - v_gold0) - (v_gold1 / 0.4 + v_gold1)) > 0.02 then raise exception 'FALHA 25: Lua Cheia pagou % na venda de %', v_gold1, (s ->> 'gold')::numeric - v_gold0; end if;
  set local role authenticated;
  s := public.sell_at_stall('batata', 90000, 'f6-moon-2-' || a);
  reset role;
  select moon_paid into v_gold1 from public.farms where user_id = a;
  if abs(v_gold1 - v_cap) > 0.02 then raise exception 'FALHA 26: Lua Cheia passou do teto: % (teto %)', v_gold1, v_cap; end if;

  -- 8. fuso: o 1º vem do aparelho e vale na hora; depois 1 troca a cada 30 dias, valendo na próxima meia-noite
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.set_timezone('Lugar/Inventado'); raise exception 'FALHA 27: aceitou fuso inválido';
  exception when check_violation then null; end;
  s := public.set_timezone('Europe/Lisbon');
  if s -> 'weather' -> 'account' ->> 'timezone' <> 'Europe/Lisbon' or not (s -> 'weather' -> 'account' ->> 'confirmed')::boolean then raise exception 'FALHA 28: fuso do aparelho %', s -> 'weather' -> 'account'; end if;
  s := public.set_timezone('America/Manaus');
  if s -> 'weather' -> 'account' ->> 'timezone' <> 'Europe/Lisbon' or s -> 'weather' -> 'account' ->> 'pending' <> 'America/Manaus' then raise exception 'FALHA 29: troca não ficou para a meia-noite'; end if;
  begin perform public.set_timezone('Asia/Tokyo'); raise exception 'FALHA 31: trocou 2 vezes em 30 dias';
  exception when check_violation then null; end;
  reset role;
  if (s -> 'weather' -> 'account' ->> 'pending_at')::timestamptz <> public.local_instant('Europe/Lisbon', (now() at time zone 'Europe/Lisbon')::date + 1, 0) then raise exception 'FALHA 30: meia-noite errada'; end if;
  if public.user_tz(b, now()) <> 'Europe/Lisbon' or public.user_tz(b, now() + interval '25 hours') <> 'America/Manaus' then raise exception 'FALHA 32: fuso pendente'; end if;

  -- 9. o jogador só vê o evento no aviso (10 min antes) e a previsão de 1 h sem Botânica
  d := (now() at time zone sp)::date;
  update public.weather_days set event_start_min = least(24 * 60 - 45, v_m + 60) where offset_min = public.tz_offset_min(sp, d) and day = d;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  reset role;
  if v_m + 60 <= 24 * 60 - 45 and s -> 'weather' -> 'event' is not null and s -> 'weather' -> 'event' <> 'null'::jsonb then raise exception 'FALHA 33: evento apareceu 1 h antes %', s -> 'weather' -> 'event'; end if;
  if (s -> 'weather' ->> 'forecast_hours')::numeric <> 1 or jsonb_array_length(s -> 'weather' -> 'forecast') not between 1 and 2 then raise exception 'FALHA 34: previsão %', s -> 'weather'; end if;

  -- 10. jogador comum não mexe no clima
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin perform public.admin_force_event(sp, d, null, null, 'tentando cancelar'); raise exception 'FALHA 35: jogador forçou evento';
  exception when insufficient_privilege then null; end;
  reset role;

  -- 11. 1 cultivo por lote: escolher num canteiro vale para os 8; semente rara de outro cultivo é recusada
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.set_crop('A1-3', 'alface');
  reset role;
  select count(*) into n from public.plots where user_id = b and plot_id like 'A1-%' and crop_id = 'alface';
  if n <> 8 then raise exception 'FALHA 36: cultivo ficou em % canteiros (esperado 8)', n; end if;
  insert into public.inventory (user_id, item_id, qty) values (b, 'seed:batata:rare', 1);
  set local role authenticated;
  begin perform public.plant_rare_seed('A1-1', 'batata', 'rare'); raise exception 'FALHA 37: plantou semente de outro cultivo no lote';
  exception when check_violation then null; end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
