-- Testes do plantio e da colheita por clique e das ferramentas de teste do admin (projeto de TESTE).
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
-- fase 6: clima desligado (este teste não depende da hora do dia)
select set_config('vif.weather', 'off', false);
do $$
declare
  a uuid := gen_random_uuid();
  adm uuid := gen_random_uuid();
  s jsonb; n int; v_labor double precision; v_gold numeric;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fc-a-' || a || '@exemplo.test', '{"nickname":"Clique A","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fc-adm-' || adm || '@exemplo.test', '{"nickname":"Clique Adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;
  update public.farms set labor_bank = 0 where user_id = a; -- sem trabalho guardado: só o clique planta na hora

  -- 1. escolher Alface no lote inteiro planta os 8 canteiros na hora, sem gastar trabalho (só a semente)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.set_crop('A1', 'alface');
  select count(*) into n from public.plots where user_id = a and plot_id like 'A1-%' and state = 'growing';
  if n <> 8 then raise exception 'FALHA 1: % canteiros plantados (esperado 8)', n; end if;
  if (s ->> 'labor_bank')::double precision <> 0 then raise exception 'FALHA 2: plantar por clique gastou trabalho'; end if;
  if (s ->> 'gold')::numeric <> 2000 - 8 * 3.7 then raise exception 'FALHA 3: sementes cobradas errado (ouro %)', s ->> 'gold'; end if;
  reset role;

  -- 2. passam 11 min: o Agricultor só juntou ~0,49 de trabalho, então nada foi colhido sozinho (colher custa 0,5)
  update public.farms set synced_at = synced_at - interval '11 minutes', last_activity_at = last_activity_at - interval '11 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if coalesce((s -> 'silo' ->> 'alface')::int, 0) <> 0 then raise exception 'FALHA 4: o Agricultor colheu sem trabalho suficiente'; end if;
  v_labor := (s ->> 'labor_bank')::double precision;

  -- 3. o clique colhe tudo que está maduro, dá XP, replanta e não gasta o trabalho guardado
  s := public.tend_farm(null);
  if coalesce((s -> 'silo' ->> 'alface')::int, 0) <> 24 then raise exception 'FALHA 5: Silo com % alfaces (esperado 24)', s -> 'silo' ->> 'alface'; end if;
  if (s ->> 'level')::int < 2 then raise exception 'FALHA 6: 1 rodada de Alface não subiu para o nível 2'; end if;
  if abs((s ->> 'labor_bank')::double precision - v_labor) > 1e-6 then raise exception 'FALHA 7: clique gastou trabalho'; end if;
  select count(*) into n from public.plots where user_id = a and plot_id like 'A1-%' and state = 'growing';
  if n <> 8 then raise exception 'FALHA 8: não replantou depois do clique (% crescendo)', n; end if;

  -- 4. alvo inválido é recusado; jogador não usa as ferramentas do admin
  begin perform public.tend_farm('A1''; drop'); raise exception 'FALHA 9: alvo inválido aceito';
  exception when check_violation then null; end;
  begin perform public.admin_set_level(a, 30, 'quero subir'); raise exception 'FALHA 10: jogador mudou o próprio nível';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_grant_gold(a, 1000000, 'quero ouro'); raise exception 'FALHA 11: jogador deu ouro a si mesmo';
  exception when insufficient_privilege then null; end;
  reset role;

  -- 5. sem clique, o Agricultor colhe e replanta na fila (0,5 + 0,5 por ciclo)
  update public.farms set labor_bank = 2.67 where user_id = a;
  update public.farms set synced_at = synced_at - interval '11 minutes', last_activity_at = last_activity_at - interval '11 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if coalesce((s -> 'silo' ->> 'alface')::int, 0) <= 24 then raise exception 'FALHA 12: o Agricultor não colheu com trabalho guardado'; end if;
  reset role;

  -- 6. admin com 2FA dá nível e ouro; fica no ledger e na auditoria
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.admin_set_level(a, 12, 'teste do pomar');
  if (s ->> 'level')::int <> 12 then raise exception 'FALHA 13: nível não mudou'; end if;
  s := public.admin_grant_gold(a, 50000, 'teste do pomar');
  if (s ->> 'gold')::numeric <> v_gold + 50000 then raise exception 'FALHA 14: ouro não entrou'; end if;
  begin perform public.admin_set_level(a, 12, 'x'); raise exception 'FALHA 15: sem justificativa aceito';
  exception when check_violation then null; end;
  reset role;
  if (select count(*) from public.audit_log where target_user_id = a and action in ('admin.set_level', 'admin.grant_gold')) <> 2 then raise exception 'FALHA 16: ações do admin sem auditoria'; end if;
  if not exists (select 1 from public.ledger where user_id = a and reason = 'admin_grant' and amount = 50000) then raise exception 'FALHA 17: ouro do admin fora do ledger'; end if;
  if (select sum(amount) from public.ledger where user_id = a) <> (select gold from public.wallets where user_id = a) then raise exception 'FALHA 18: ledger × carteira'; end if;

  -- 7. admin termina a limpeza: o lote fica pronto e o canteiro planta na hora; jogador não consegue
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.buy_lot('A3');
  begin perform public.admin_finish_cleanup(a, null, 'quero pular a espera'); raise exception 'FALHA 19: jogador terminou a limpeza';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_finish_cleanup(a, 'A3', 'teste da limpeza');
  begin perform public.admin_finish_cleanup(a, 'A3', 'teste da limpeza'); raise exception 'FALHA 20: limpeza terminada duas vezes';
  exception when check_violation then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.set_crop('A3', 'alface');
  select count(*) into n from public.plots where user_id = a and plot_id like 'A3-%' and state = 'growing';
  if n <> 8 then raise exception 'FALHA 21: % canteiros do A3 plantados depois da limpeza (esperado 8)', n; end if;
  reset role;
  if not exists (select 1 from public.audit_log where target_user_id = a and action = 'admin.finish_cleanup' and actor_id = adm) then raise exception 'FALHA 22: limpeza sem auditoria'; end if;

  raise exception 'TESTES_OK';
end $$;
