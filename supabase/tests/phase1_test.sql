-- Testes da fase 1 (rodar no projeto de TESTE). Tudo é desfeito no fim:
-- o resultado esperado é o erro "TESTES_OK"; qualquer "FALHA ..." diz o que quebrou.
-- Dentro de uma transação now() é fixo, então "passar o tempo" = recuar synced_at e last_activity_at.
-- fase 6: clima desligado (este teste não depende da hora do dia)
select set_config('vif.weather', 'off', false);
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  s jsonb;
  n int;
  g numeric;
  t double precision;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-a-' || a || '@exemplo.test', '{"nickname":"Fazenda A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-b-' || b || '@exemplo.test', '{"nickname":"Fazenda B","birth_date":"1990-01-01"}', now(), now());

  -- (desde a fase 2 a Batata pede nível 2)
  update public.farms set level = 2 where user_id = a;

  -- 1. conta nova ganha o A1 com 8 canteiros e 1 h de trabalho guardado
  select count(*) into n from public.plots where user_id = a and plot_id like 'A1-%';
  if n <> 8 then raise exception 'FALHA 1: % canteiros no A1', n; end if;
  if abs((select labor_bank from public.farms where user_id = a) - 2.67) > 1e-6 then raise exception 'FALHA 2: trabalho inicial'; end if;

  -- 2. como o jogador A: planta Batata no A1-1; com trabalho guardado, planta na hora
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.set_crop('A1-1', 'batata');
  if (select state from public.plots where user_id = a and plot_id = 'A1-1') <> 'growing' then raise exception 'FALHA 3: não plantou'; end if;
  if (s ->> 'gold')::numeric <> 1978 then raise exception 'FALHA 4: semente cobrada errado (ouro %)', s ->> 'gold'; end if;
  begin
    perform public.set_crop('A1-2', 'morango');
    raise exception 'FALHA 5: cultivo não liberado aceito';
  exception when check_violation then null;
  end;
  begin
    perform public.set_crop('A2-1', 'batata');
    raise exception 'FALHA 6: plantou em lote que não é dele';
  exception when check_violation then null;
  end;
  reset role;

  -- 3. passam 2 h: colhe às 1 h e às 2 h, replanta sozinho
  update public.farms set synced_at = synced_at - interval '2 hours', last_activity_at = last_activity_at - interval '2 hours' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'silo' ->> 'batata')::int <> 6 then raise exception 'FALHA 7: Silo com % batatas (esperado 6)', s -> 'silo' ->> 'batata'; end if;
  if (s ->> 'gold')::numeric <> 1934 then raise exception 'FALHA 8: ouro % (esperado 1934)', s ->> 'gold'; end if;
  if abs((s ->> 'farm_time')::double precision - 7200) > 1e-6 then raise exception 'FALHA 9: relógio da fazenda %', s ->> 'farm_time'; end if;

  -- 4. Barraca: 70% do preço da Feira; a mesma venda repetida não paga de novo
  s := public.sell_at_stall('batata', 6, 'teste-venda-1');
  if (s ->> 'gold')::numeric <> 1934 + 6 * 29 * 0.7 then raise exception 'FALHA 10: venda pagou %', s ->> 'gold'; end if;
  s := public.sell_at_stall('batata', 6, 'teste-venda-1');
  if (s ->> 'gold')::numeric <> 1934 + 6 * 29 * 0.7 then raise exception 'FALHA 11: venda repetida pagou de novo'; end if;
  begin
    perform public.sell_at_stall('batata', 1, 'teste-venda-2');
    raise exception 'FALHA 12: vendeu sem ter no Silo';
  exception when check_violation then null;
  end;
  reset role;

  -- 5. limite offline: fora 10 h, a fazenda anda só 8 h
  select farm_time into t from public.farms where user_id = a;
  update public.farms set synced_at = synced_at - interval '10 hours', last_activity_at = last_activity_at - interval '10 hours' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if abs((s ->> 'farm_time')::double precision - t - 8 * 3600) > 1e-6 then raise exception 'FALHA 13: andou % s (esperado 8 h)', (s ->> 'farm_time')::double precision - t; end if;
  -- trabalho de 8 h com 1 Agricultor (2,67/h, teto de 1 h guardada): no máximo 1 + 8 × 2,67 plantios
  select count(*) into n from public.ledger where user_id = a and reason = 'seeds';
  reset role;

  -- 6. sem ouro, o canteiro para (sem_ouro) e volta depois de vender
  perform public.ledger_post(a, -(select gold from public.wallets where user_id = a), 'test_spend');
  update public.farms set synced_at = synced_at - interval '2 hours', last_activity_at = last_activity_at - interval '2 hours' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (select stalled_reason from public.plots where user_id = a and plot_id = 'A1-1') is distinct from 'sem_ouro' then raise exception 'FALHA 14: canteiro não parou sem ouro'; end if;
  s := public.sell_at_stall('batata', (s -> 'silo' ->> 'batata')::int, 'teste-venda-3');
  -- (fase 3: o Agricultor pode estar sem energia depois de 8 h; o canteiro só precisa deixar de estar parado)
  if (select stalled_reason from public.plots where user_id = a and plot_id = 'A1-1') is not null then raise exception 'FALHA 15: não voltou a plantar depois da venda'; end if;
  -- ledger continua batendo com a carteira
  if (select sum(amount) from public.ledger where user_id = a) <> (s ->> 'gold')::numeric then raise exception 'FALHA 16: ledger diferente da carteira'; end if;

  -- 7. outro jogador não vê nada da fazenda de A
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.plots where user_id = a;
  if n <> 0 then raise exception 'FALHA 17: B vê canteiros de A'; end if;
  select count(*) into n from public.silo where user_id = a;
  if n <> 0 then raise exception 'FALHA 18: B vê o Silo de A'; end if;
  begin
    perform public.advance_farm(a, now());
    raise exception 'FALHA 19: jogador chama advance_farm direto';
  exception when insufficient_privilege then null;
  end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
