-- Testes da fase 2 (projeto de TESTE). Esperado: erro "TESTES_OK" (tudo é desfeito).
-- "Passar o tempo" = recuar synced_at e last_activity_at (no máximo 8 h por vez, o limite offline).
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  adm uuid := gen_random_uuid();
  s jsonb; n int; r record;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f2-a-' || a || '@exemplo.test', '{"nickname":"Fase2 A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f2-b-' || b || '@exemplo.test', '{"nickname":"Fase2 B","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f2-adm-' || adm || '@exemplo.test', '{"nickname":"Fase2 Adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;

  -- 1. nível 1: só Alface e Cenoura; lote exige nível 2
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.set_crop('A1-1', 'batata'); raise exception 'FALHA 1: Batata no nível 1';
  exception when check_violation then null; end;
  begin perform public.buy_lot('A3'); raise exception 'FALHA 2: lote comprado no nível 1';
  exception when check_violation then if sqlerrm <> 'nível insuficiente' then raise exception 'FALHA 2b: %', sqlerrm; end if; end;
  s := public.set_crop('A1-1', 'alface');
  reset role;

  -- 2. colheita dá XP e sobe de nível (Alface = 5,1 XP; nível 1→2 pede o xp_to_next da config)
  update public.farms set xp = (public.config_get('levels') -> 'levels' -> 0 ->> 'xp_to_next')::numeric - 5 where user_id = a;
  update public.farms set synced_at = synced_at - interval '11 minutes', last_activity_at = last_activity_at - interval '11 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (s ->> 'level')::int <> 2 then raise exception 'FALHA 3: nível % (esperado 2)', s ->> 'level'; end if;
  reset role;
  if not exists (select 1 from public.audit_log where target_user_id = a and action = 'level.up') then raise exception 'FALHA 4: subida de nível sem auditoria'; end if;
  set local role authenticated;
  s := public.set_crop('A1-2', 'batata'); -- agora liberada

  -- 3. comprar lote vizinho (A3), recusar não vizinho (A2)
  s := public.buy_lot('A3');
  if not exists (select 1 from public.owned_lots where user_id = a and lot_id = 'A3' and purchase_n = 1) then raise exception 'FALHA 5: A3 não comprado'; end if;
  if (select count(*) from public.plots where user_id = a and plot_id like 'A3-%') <> 8 then raise exception 'FALHA 6: A3 sem 8 canteiros'; end if;
  if (select amount from public.ledger where user_id = a and reason = 'lot_purchase') <> -(public.config_get('lots') -> 'purchases' -> 0 ->> 'cost')::numeric then raise exception 'FALHA 7: preço do 1º lote'; end if;
  begin perform public.buy_lot('A2'); raise exception 'FALHA 8: comprou lote não vizinho';
  exception when check_violation then if sqlerrm <> 'lote não é vizinho' then raise exception 'FALHA 8b: %', sqlerrm; end if; end;
  begin perform public.buy_lot('A3'); raise exception 'FALHA 9: comprou o mesmo lote duas vezes';
  exception when check_violation then null; end;
  reset role;

  -- 4. limpeza: 1 h + 12 min × 1, em dobro sem Ferreiro = 144 min; antes disso o A3 não planta
  set local role authenticated;
  s := public.set_crop('A1', null);   -- para o A1, para o trabalho sobrar para o A3
  s := public.set_crop('A3', 'alface');
  reset role;
  update public.farms set synced_at = synced_at - interval '60 minutes', last_activity_at = last_activity_at - interval '60 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if exists (select 1 from public.plots where user_id = a and plot_id like 'A3-%' and state = 'growing') then raise exception 'FALHA 10: plantou durante a limpeza'; end if;
  reset role;
  update public.farms set synced_at = synced_at - interval '100 minutes', last_activity_at = last_activity_at - interval '100 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if not exists (select 1 from public.plots where user_id = a and plot_id like 'A3-%' and state = 'growing') then raise exception 'FALHA 11: não plantou depois da limpeza'; end if;
  reset role;

  -- 5. Galinheiro pode ser comprado longe (nível 3)
  update public.farms set level = 3 where user_id = a;
  set local role authenticated;
  s := public.buy_lot('C1');
  if not exists (select 1 from public.owned_lots where user_id = a and lot_id = 'C1') then raise exception 'FALHA 12: Galinheiro não comprado de longe'; end if;
  reset role;

  -- 6. da 20ª compra em diante precisa de Escritura (dada pelo painel do admin)
  insert into public.owned_lots (user_id, lot_id, purchase_n)
    select a, x ->> 'id', 100 from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x
    where x ->> 'id' in ('A4','A2','A5','A6','A7','A8','A9','A10','A11','A12','A13','A14','A15','A16','A17','P2','P3'); -- 20 lotes: a próxima é a 20ª compra
  update public.farms set level = 30 where user_id = a;
  perform public.ledger_post(a, 20000000, 'test_grant');
  set local role authenticated;
  begin perform public.buy_lot('P5'); raise exception 'FALHA 13: 20ª compra sem Escritura';
  exception when check_violation then if sqlerrm <> 'precisa de Escritura' then raise exception 'FALHA 13b: %', sqlerrm; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  perform public.admin_grant_item(a, 'deed', 1, 'teste da fase 2');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.buy_lot('P5');
  if (s -> 'inventory' ->> 'deed') is not null then raise exception 'FALHA 14: Escritura não foi gasta'; end if;
  if (select purchase_n from public.owned_lots where user_id = a and lot_id = 'P5') <> 20 then raise exception 'FALHA 15: nº da compra %', (select purchase_n from public.owned_lots where user_id = a and lot_id = 'P5'); end if;
  reset role;

  -- 7. pomar: muda só depois da limpeza, colhe sozinho, derruba grátis, fruta respeita o nível
  update public.farms set level = 11 where user_id = b;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.buy_lot('P1'); -- vizinho do A1; pomar exige nível 10
  begin perform public.plant_tree('P1', 1, 'maca'); raise exception 'FALHA 16: plantou árvore na limpeza';
  exception when check_violation then null; end;
  reset role;
  perform public.ledger_post(b, 50000, 'test_grant');
  update public.farms set synced_at = synced_at - interval '3 hours', last_activity_at = last_activity_at - interval '3 hours' where user_id = b;
  set local role authenticated;
  s := public.plant_tree('P1', 1, 'maca');
  if (select fruit_id from public.trees where user_id = b and lot_id = 'P1' and slot = 1) <> 'maca' then raise exception 'FALHA 17: muda não plantada'; end if;
  reset role;
  -- Maçã: cresce 12 h; o relógio anda no máximo 8 h por volta
  update public.farms set synced_at = synced_at - interval '8 hours', last_activity_at = last_activity_at - interval '8 hours' where user_id = b;
  set local role authenticated; s := public.get_farm(); reset role;
  update public.farms set synced_at = synced_at - interval '5 hours', last_activity_at = last_activity_at - interval '5 hours' where user_id = b;
  set local role authenticated;
  s := public.get_farm();
  if coalesce((s -> 'silo' ->> 'maca')::int, 0) <> 4 then raise exception 'FALHA 18: Silo com % maçãs (esperado 4)', s -> 'silo' ->> 'maca'; end if;
  s := public.chop_tree('P1', 1);
  if (select fruit_id from public.trees where user_id = b and lot_id = 'P1' and slot = 1) is not null then raise exception 'FALHA 19: árvore não derrubada'; end if;
  begin perform public.plant_tree('P1', 1, 'laranja'); raise exception 'FALHA 20: Laranja (nível 15) no nível 11';
  exception when check_violation then null; end;
  select count(*) into n from public.ledger where user_id = b and reason like '%chop%';
  if n <> 0 then raise exception 'FALHA 21: derrubar cobrou ouro'; end if;
  reset role;

  -- 8. recorrente: Morango dá 5 colheitas com 1 semente só
  update public.farms set level = 4, labor_bank = 2.67 where user_id = b;
  set local role authenticated;
  s := public.set_crop('A1-1', 'morango');
  reset role;
  for n in 1 .. 2 loop
    update public.farms set synced_at = synced_at - interval '4 hours', last_activity_at = last_activity_at - interval '4 hours' where user_id = b;
    set local role authenticated; s := public.get_farm(); reset role;
  end loop;
  -- 1,5 h + 4 × 1 h = 5,5 h: as 5 colheitas (10 morangos) e depois replanta
  if coalesce((s -> 'silo' ->> 'morango')::int, 0) < 10 then raise exception 'FALHA 22: % morangos (esperado 10 ou mais)', s -> 'silo' ->> 'morango'; end if;
  select count(*) into n from public.ledger where user_id = b and reason = 'seeds';
  if (select sum(amount) from public.ledger where user_id = b and reason = 'seeds') > -100 then raise exception 'FALHA 23: semente do morango não cobrada'; end if;

  -- 9. ferramenta: Cobre só no nível 8; aumenta o trabalho em 40%
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.upgrade_tool('agricultor'); raise exception 'FALHA 24: Cobre no nível 4';
  exception when check_violation then null; end;
  reset role;
  update public.farms set level = 8 where user_id = b;
  set local role authenticated;
  s := public.upgrade_tool('agricultor');
  if (s -> 'tools' ->> 'agricultor') <> 'copper' or abs((s ->> 'labor_per_hour')::numeric - 2.67 * 1.4) > 0.001 then
    raise exception 'FALHA 25: ferramenta % trabalho %', s -> 'tools' ->> 'agricultor', s ->> 'labor_per_hour';
  end if;
  begin perform public.admin_grant_item(b, 'deed', 1, 'auto-presente'); raise exception 'FALHA 26: jogador deu Escritura a si mesmo';
  exception when insufficient_privilege then null; end;
  reset role;

  -- 10. ledger continua batendo com a carteira
  for r in select u, (select sum(amount) from public.ledger where user_id = u) as total, (select gold from public.wallets where user_id = u) as gold
           from unnest(array[a, b]) u loop
    if r.total <> r.gold then raise exception 'FALHA 27: ledger % × carteira %', r.total, r.gold; end if;
  end loop;

  raise exception 'TESTES_OK';
end $$;
