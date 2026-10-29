-- Testes da fase 9: papéis do painel (Leitor, Moderador, Admin, sempre com 2FA), advertir/suspender/banir, reverter lançamento,
-- regras do antitrapaça (renda, progresso, cartas, sorte, robô, recusas, minigame, relógio e fuso), nota de risco, filas e guias.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); rd uuid := gen_random_uuid(); md uuid := gen_random_uuid(); ad uuid := gen_random_uuid();
  s jsonb; v_gold numeric; v_id bigint; k int; t timestamptz := now();
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f9-a-' || a || '@exemplo.test', '{"nickname":"Fase9A","birth_date":"1990-01-01"}', now(), now()),
    (rd, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f9-r-' || rd || '@exemplo.test', '{"nickname":"Fase9Leitor","birth_date":"1990-01-01"}', now(), now()),
    (md, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f9-m-' || md || '@exemplo.test', '{"nickname":"Fase9Mod","birth_date":"1990-01-01"}', now(), now()),
    (ad, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f9-ad-' || ad || '@exemplo.test', '{"nickname":"Fase9Adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set admin_role = 'reader' where id = rd;
  update public.profiles set admin_role = 'moderator' where id = md;
  update public.profiles set is_admin = true, admin_role = 'admin' where id = ad;

  -- 1. papéis: Leitor só vê; Moderador advertir/suspender; banir só Admin; sem 2FA nada
  perform set_config('request.jwt.claims', json_build_object('sub', rd, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_overview();
  if not s ? 'dau' then raise exception 'FALHA 1: leitor sem visão geral'; end if;
  begin perform public.admin_set_status(a, 'warned', null, 'aviso', 'teste do leitor'); raise exception 'FALHA 2: leitor advertiu';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', md, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  set local role authenticated;
  begin perform public.admin_overview(); raise exception 'FALHA 3: sem 2FA';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', md, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_set_status(a, 'warned', null, 'Seja gentil nos recados.', 'teste do moderador');
  begin perform public.admin_set_status(a, 'banned', null, '', 'teste do moderador'); raise exception 'FALHA 4: moderador baniu';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_grant_gold(a, 100, 'teste do moderador'); raise exception 'FALHA 5: moderador deu ouro';
  exception when insufficient_privilege then null; end;
  reset role;

  -- 2. a advertência aparece para o jogador uma vez
  if public.social_badge(a) -> 'account' ->> 'warning' <> 'Seja gentil nos recados.' then raise exception 'FALHA 6: advertência %', public.social_badge(a) -> 'account'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.warning_seen();
  reset role;
  if public.social_badge(a) -> 'account' ->> 'warning' is not null then raise exception 'FALHA 7: advertência não sumiu'; end if;

  -- 3. suspensa não joga; volta a jogar quando reativada; banida não joga
  perform set_config('request.jwt.claims', json_build_object('sub', md, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_set_status(a, 'suspended', 3, 'Suspensa por 3 dias.', 'teste do moderador');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.get_farm(); raise exception 'FALHA 8: suspensa jogou';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_set_status(a, 'active', null, '', 'teste do admin');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  reset role;
  if not exists (select 1 from public.audit_log where action = 'admin.set_status' and actor_id = md and target_user_id = a) then raise exception 'FALHA 9: sem registro'; end if;

  -- 4. reverter lançamento: lança o contrário uma vez só; reversão não se reverte
  perform public.ledger_post(a, 5000, 'stall_sale', '{}');
  select id into v_id from public.ledger where user_id = a and reason = 'stall_sale' order by id desc limit 1;
  select gold into v_gold from public.wallets where user_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_revert_ledger(v_id, 'teste do admin');
  s := public.admin_revert_ledger(v_id, 'teste do admin');
  reset role;
  select id into v_id from public.ledger where user_id = a and reason = 'admin_revert' limit 1;
  set local role authenticated;
  begin perform public.admin_revert_ledger(v_id, 'teste do admin'); raise exception 'FALHA 10: reverteu reversão';
  exception when check_violation then null; end;
  reset role;
  if (select gold from public.wallets where user_id = a) <> v_gold - 5000 then raise exception 'FALHA 11: reversão %', (select gold from public.wallets where user_id = a) - v_gold; end if;

  -- 5. antitrapaça: cada regra gera seu alerta
  perform public.ledger_post(a, public.ref_income(30) * 5, 'stall_sale', '{}');                     -- renda impossível (para o nível 30 abaixo)
  update public.farms set level = 30 where user_id = a;                                             -- nível 30 com conta de 0 dia
  insert into public.cards (user_id, card_id, rarity, origin) select a, 'sol_de_verao', 'common', 'daily_pack' from generate_series(1, 11);
  insert into public.expeditions (user_id, convoy_id, vehicle_id, route_id, cargo, cargo_value, minigame, chance, started_at, returns_at, status, outcome)
    select a, gen_random_uuid(), 'carroca', 'feira', '{}', 0, 'done', 0.3, 0, 0, 'back', 'success' from generate_series(1, 30);
  insert into public.action_times (user_id, at) select a, now() - make_interval(secs => g) from generate_series(1, 80) g;   -- 1 ação por segundo, exata
  for k in 1 .. 25 loop perform public.log_refusal('buy_lot', 'ouro insuficiente'); end loop;     -- sem login não grava
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  for k in 1 .. 25 loop perform public.log_refusal('buy_lot', 'ouro insuficiente'); end loop;
  s := public.client_ping((extract(epoch from now()) * 1000)::bigint - 600000, 'Europe/Lisbon');    -- relógio 10 min atrás, fuso diferente
  reset role;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (a, 'cheat.minigame_robot', a, '{}');
  update public.profiles set tz_mismatch_since = now() - interval '8 days' where id = a;
  perform public.anticheat_check(a, true);
  for s in select to_jsonb(x) from (values ('income'), ('progress'), ('cards'), ('luck'), ('robot'), ('refusals'), ('minigame_robot'), ('timezone'), ('clock')) x(r) loop
    if not exists (select 1 from public.alerts where user_id = a and rule = s ->> 'r') then raise exception 'FALHA 12: regra % não disparou', s ->> 'r'; end if;
  end loop;
  -- não repete o mesmo alerta em 24 h; nota de risco no teto; mercado congelado a partir de 90
  perform public.anticheat_check(a, true);
  if (select count(*) from public.alerts where user_id = a and rule = 'income') <> 1 then raise exception 'FALHA 13: alerta repetido'; end if;
  if public.account_risk(a) <> 100 then raise exception 'FALHA 14: risco %', public.account_risk(a); end if;
  if not (select market_frozen from public.profiles where id = a) then raise exception 'FALHA 15: mercado não congelou'; end if;
  -- a sincronização automática não conta como clique; as ações contam no dia
  delete from public.action_times where user_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  reset role;
  if exists (select 1 from public.action_times where user_id = a) then raise exception 'FALHA 16: sincronização contou como clique'; end if;
  perform public.touch_farm(a);
  if not exists (select 1 from public.action_times where user_id = a) or not exists (select 1 from public.farm_days where user_id = a and actions >= 2) then
    raise exception 'FALHA 17: atividade não registrada'; end if;

  -- 6. filas: moderador arquiva alerta e fecha denúncia; leitor vê as guias
  insert into public.player_reports (reporter, target, reason, day) values (md, a, 'apelido', current_date);
  select id into v_id from public.alerts where user_id = a and rule = 'income';
  select id into k from public.player_reports where target = a limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', md, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_alert_set(v_id, 'archived', 'era teste');
  s := public.admin_report_close(k, 'conferido');
  reset role;
  if (select status from public.alerts where user_id = a and rule = 'income') <> 'archived' then raise exception 'FALHA 18: alerta não arquivou'; end if;
  if (select status from public.player_reports where target = a limit 1) <> 'closed' then raise exception 'FALHA 19: denúncia não fechou'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', rd, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_economy(7); s := public.admin_progress(); s := public.admin_expeditions(); s := public.admin_cards(); s := public.admin_missions();
  s := public.admin_config_versions('village'); s := public.admin_audit_admins(50); s := public.admin_player_summary(a); s := public.admin_alerts('all', 50);
  if (s -> 0 ->> 'user_id') is null then raise exception 'FALHA 20: fila de alertas vazia'; end if;
  begin perform public.admin_config_restore('village', 1, 'teste do leitor'); raise exception 'FALHA 21: leitor mudou config';
  exception when insufficient_privilege then null; end;
  reset role;

  -- 7. admin: voltar versão de config cria versão nova igual à antiga; papel novo; alerta de teste
  perform set_config('request.jwt.claims', json_build_object('sub', ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_config_restore('village', 1, 'teste do admin');
  s := public.admin_set_role(a, 'reader', 'teste do admin');
  s := public.admin_test_alert();
  reset role;
  if (select data - 'version' - 'restored_from' from public.game_config where name = 'village' order by version desc limit 1)
     <> (select data - 'version' from public.game_config where name = 'village' and version = 1) then raise exception 'FALHA 22: config restaurada diferente'; end if;
  if (select admin_role from public.profiles where id = a) <> 'reader' then raise exception 'FALHA 23: papel'; end if;
  if not exists (select 1 from public.audit_log where action = 'admin.test_alert' and actor_id = ad) then raise exception 'FALHA 24: alerta de teste'; end if;

  raise exception 'TESTES_OK';
end $$;
