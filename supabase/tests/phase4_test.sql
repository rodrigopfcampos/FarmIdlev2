-- Testes da fase 4: animais, vagas, Lago, ração por ciclo, coleta (clique e equipe), fome, ampliação, venda e segurança.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
-- fase 6: clima desligado (este teste não depende da hora do dia)
select set_config('vif.weather', 'off', false);
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  s jsonb; n int; v_gold numeric; v_t double precision; v_q int; v_feed numeric;
  feed_galinha numeric := round(740 * 120 / 1440.0, 2);
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f4-a-' || a || '@exemplo.test', '{"nickname":"Fase4 A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f4-b-' || b || '@exemplo.test', '{"nickname":"Fase4 B","birth_date":"1990-01-01"}', now(), now());
  update public.farms set level = 3 where user_id = a;
  perform public.ledger_post(a, 100000, 'test_grant');

  -- 1. sem o pasto não há Galinheiro
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.buy_animal('galinheiro', 1, 'galinha'); raise exception 'FALHA 1: comprou animal sem o Galinheiro';
  exception when check_violation then null; end;
  s := public.buy_lot('C1');
  begin perform public.buy_animal('galinheiro', 1, 'galinha'); raise exception 'FALHA 2: comprou com o pasto em limpeza';
  exception when check_violation then null; end;
  reset role;
  update public.owned_lots set ready_at = 0 where user_id = a and lot_id = 'C1';

  -- 2. comprar a Galinha: preço da compra + ração do 1º ciclo; raridade sorteada; pronta em 2 h
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.buy_animal('galinheiro', 1, 'galinha');
  if (s ->> 'gold')::numeric <> v_gold - 7400 - feed_galinha then raise exception 'FALHA 3: compra cobrou % (esperado %)', v_gold - (s ->> 'gold')::numeric, 7400 + feed_galinha; end if;
  if s -> 'animals' -> 0 ->> 'rarity' not in ('common', 'uncommon', 'rare', 'legendary', 'mythic') then raise exception 'FALHA 4: raridade não sorteada'; end if;
  if abs((s -> 'animals' -> 0 ->> 'ready_at')::double precision - (s ->> 'farm_time')::double precision - 7200) > 1 then raise exception 'FALHA 5: ciclo da Galinha não é 2 h'; end if;
  if (s -> 'houses' -> 'galinheiro' ->> 'slots')::int <> 4 or (s -> 'houses' -> 'galinheiro' ->> 'bird_slots')::int <> 0 then raise exception 'FALHA 6: vagas do Galinheiro erradas'; end if;
  -- regras da vaga
  begin perform public.buy_animal('galinheiro', 1, 'galinha'); raise exception 'FALHA 7: vaga ocupada aceita';
  exception when check_violation then null; end;
  begin perform public.buy_animal('galinheiro', 5, 'galinha'); raise exception 'FALHA 8: vaga 5 sem ampliação e sem Lago';
  exception when check_violation then null; end;
  begin perform public.buy_animal('galinheiro', 2, 'vaca'); raise exception 'FALHA 9: Vaca no Galinheiro';
  exception when check_violation then null; end;
  begin perform public.buy_animal('galinheiro', 2, 'coelho'); raise exception 'FALHA 10: Coelho antes do nível 6';
  exception when check_violation then null; end;
  reset role;
  update public.animals set rarity = 'common' where user_id = a;

  -- 3. clique coleta 1 ovo (Comum, 100%), dá XP e começa outro ciclo cobrando a ração
  update public.animals set ready_at = 0 where user_id = a;
  update public.characters set energy = 0, parked = true where user_id = a; -- ninguém da equipe trabalha
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.tend_farm('C1');
  if coalesce((s -> 'silo' ->> 'ovo')::int, 0) <> 1 then raise exception 'FALHA 11: clique coletou % ovos', s -> 'silo' ->> 'ovo'; end if;
  if (s ->> 'gold')::numeric <> v_gold - feed_galinha then raise exception 'FALHA 12: ração do novo ciclo não cobrada'; end if;
  if (s -> 'animals' -> 0 ->> 'ready_at')::double precision <= (s ->> 'farm_time')::double precision then raise exception 'FALHA 13: não começou outro ciclo'; end if;
  reset role;

  -- 4. sem ouro o animal fica com fome; vender o ovo devolve ouro e ele volta a produzir
  perform public.ledger_post(a, -(select gold from public.wallets where user_id = a), 'test_spend');
  update public.animals set ready_at = 0 where user_id = a;
  set local role authenticated;
  s := public.tend_farm('C1');
  if s -> 'animals' -> 0 ->> 'state' <> 'hungry' then raise exception 'FALHA 14: sem ouro não ficou com fome'; end if;
  s := public.sell_at_stall('ovo', 2, 'teste-ovo-venda-1');
  if (s ->> 'gold')::numeric <> round(2 * 410 * 0.7, 2) - feed_galinha then raise exception 'FALHA 15: venda do ovo ou volta da ração errada (ouro %)', s ->> 'gold'; end if;
  if s -> 'animals' -> 0 ->> 'state' <> 'growing' then raise exception 'FALHA 16: não voltou a produzir depois da venda'; end if;
  reset role;

  -- 5. fora do jogo a equipe coleta na fila (sem Rancheira: 60%) e começa o próximo ciclo
  perform public.ledger_post(a, 100000, 'test_grant');
  update public.characters set energy = 100, parked = false where user_id = a;
  update public.animals set ready_at = (select farm_time from public.farms where user_id = a) where user_id = a;
  update public.farms set labor_bank = 2, synced_at = synced_at - interval '10 minutes' where user_id = a;
  select coalesce((select qty from public.silo where user_id = a and item_id = 'ovo'), 0) into v_q;
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'animals' -> 0 ->> 'ready_at')::double precision <= (s ->> 'farm_time')::double precision then raise exception 'FALHA 17: a equipe não coletou'; end if;
  if coalesce((s -> 'silo' ->> 'ovo')::int, 0) - v_q not in (0, 1) then raise exception 'FALHA 18: equipe sem Rancheira coletou %', coalesce((s -> 'silo' ->> 'ovo')::int, 0) - v_q; end if;
  reset role;
  if not exists (select 1 from public.ledger where user_id = a and reason = 'feed' and ref ? 'farm_time') then raise exception 'FALHA 19: ração da equipe fora do ledger'; end if;

  -- 6. ampliar o Galinheiro (nível 9): 8 vagas
  update public.farms set level = 9 where user_id = a;
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.upgrade_house('galinheiro');
  if (s -> 'houses' -> 'galinheiro' ->> 'slots')::int <> 8 or (s ->> 'gold')::numeric <> v_gold - 39000 then raise exception 'FALHA 20: ampliação errada'; end if;
  s := public.buy_animal('galinheiro', 8, 'coelho');

  -- 7. Lago: +2 vagas só para aves
  reset role;
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (a, 'L', 0, 9);
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'houses' -> 'galinheiro' ->> 'bird_slots')::int <> 2 or not (s ->> 'lake')::boolean then raise exception 'FALHA 21: Lago não deu 2 vagas de ave'; end if;
  begin perform public.buy_animal('galinheiro', 9, 'coelho'); raise exception 'FALHA 22: Coelho na vaga do Lago';
  exception when check_violation then null; end;
  s := public.buy_animal('galinheiro', 9, 'galinha');

  -- 8. tirar o animal não devolve ouro
  select gold into v_gold from public.wallets where user_id = a;
  s := public.remove_animal('galinheiro', 9);
  if (s ->> 'gold')::numeric <> v_gold then raise exception 'FALHA 23: tirar o animal mexeu no ouro'; end if;
  if exists (select 1 from public.animals where user_id = a and house_id = 'galinheiro' and slot = 9) then raise exception 'FALHA 24: animal não saiu'; end if;
  reset role;

  -- 9. Lago e Gato aumentam a produção das aves: Galinha Mítica com Lago coleta round(3 × 1,1) = 3 ou 4
  update public.animals set rarity = 'mythic', ready_at = 0, state = 'growing' where user_id = a and slot = 1;
  delete from public.silo where user_id = a and item_id = 'ovo';
  update public.characters set energy = 0, parked = true where user_id = a;
  set local role authenticated;
  s := public.tend_farm('C1');
  if (s -> 'silo' ->> 'ovo')::int not in (3, 4) then raise exception 'FALHA 25: Galinha Mítica com Lago coletou %', s -> 'silo' ->> 'ovo'; end if;
  reset role;

  -- 10. segurança: B não vê os animais de A; ninguém escreve direto; funções internas fechadas
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.animals where user_id = a;
  if n <> 0 then raise exception 'FALHA 26: B vê os animais de A'; end if;
  begin insert into public.animals (user_id, house_id, slot, animal_id, rarity) values (b, 'galinheiro', 1, 'alpaca', 'mythic'); raise exception 'FALHA 27: jogador criou animal direto';
  exception when insufficient_privilege then null; end;
  begin perform public.animal_collect(a, 'galinheiro', 1, 0, '{}'::jsonb, false); raise exception 'FALHA 28: jogador chamou função interna';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_finish_animals(a, 'quero testar'); raise exception 'FALHA 29: jogador usou ferramenta do admin';
  exception when insufficient_privilege then null; end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
