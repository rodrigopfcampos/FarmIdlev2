-- Testes da fase 5: Garagem, minigame, lançamento, comboio, volta com clique, falha parcial, seguro, garantia contra
-- azar, repetição, Gerente conduzindo, reforma com Kit, juntar 3 iguais, equipar item, conserto, demanda e segurança.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  s jsonb; mg jsonb; keys jsonb; n int; v_gold numeric; v_q int; v_id uuid; x public.expeditions; v_ch double precision;
  v_dem text[];
  -- teclas certas com intervalos variados (humano)
  ts int[] := array[180, 410, 600, 870, 1090, 1320, 1580, 1800, 2050, 2290, 2560, 2780];
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f5-a-' || a || '@exemplo.test', '{"nickname":"Fase5 A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f5-b-' || b || '@exemplo.test', '{"nickname":"Fase5 B","birth_date":"1990-01-01"}', now(), now());
  perform public.ledger_post(a, 1000000, 'test_grant');
  insert into public.silo (user_id, item_id, qty) values (a, 'batata', 500), (a, 'alface', 500);

  -- 1. a fazenda nova já tem a Carroça ativa; a demanda do dia existe (3 produtos por rota, igual para todos)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  if s -> 'vehicles' -> 0 ->> 'vehicle_id' <> 'carroca' or not (s -> 'vehicles' -> 0 ->> 'active')::boolean then raise exception 'FALHA 1: sem Carroça ativa'; end if;
  if jsonb_array_length(s -> 'demand' -> 'feira') <> 3 then raise exception 'FALHA 2: demanda do dia errada'; end if;
  reset role;

  -- 2. minigame: setas e tempo da rota; comboio soma setas e tempo
  set local role authenticated;
  mg := public.start_minigame('feira', 1, false, false);
  if jsonb_array_length(mg -> 'arrows') <> 4 or (mg ->> 'limit_ms')::int <> 6000 then raise exception 'FALHA 3: minigame da Feira %', mg; end if;
  -- 3. não dá para lançar além do que o veículo alcança nem rota sem nível
  begin perform public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'capital', '{"batata":10}', false, false, false);
    raise exception 'FALHA 4: lançou na Capital'; exception when check_violation then null; end;
  mg := public.start_minigame('feira', 1, false, false);
  select jsonb_agg(jsonb_build_object('k', k, 't', ts[o])) into keys from jsonb_array_elements_text(mg -> 'arrows') with ordinality z(k, o);
  s := public.launch_expedition((mg ->> 'id')::uuid, keys, array['carroca'], 'feira', '{"batata":40,"alface":20}', false, false, false);
  if s -> 'minigame' ->> 'result' <> 'perfect' then raise exception 'FALHA 5: minigame humano sem erro deu %', s -> 'minigame'; end if;
  if (s -> 'silo' ->> 'batata')::int <> 460 or (s -> 'silo' ->> 'alface')::int <> 480 then raise exception 'FALHA 6: carga não saiu do Silo'; end if;
  if s -> 'expeditions' -> 0 ->> 'status' <> 'travel' or s -> 'expeditions' -> 0 ? 'outcome' then raise exception 'FALHA 7: estado da viagem errado'; end if;
  if abs((s -> 'expeditions' -> 0 ->> 'returns_at')::double precision - (s -> 'expeditions' -> 0 ->> 'started_at')::double precision - 0.5 * 1.3 * 3600) > 1 then
    raise exception 'FALHA 8: duração da Carroça na Feira'; end if;
  -- o mesmo minigame não serve duas vezes; veículo viajando não sai de novo
  begin perform public.launch_expedition((mg ->> 'id')::uuid, keys, array['carroca'], 'feira', '{"batata":10}', false, false, false);
    raise exception 'FALHA 9: minigame reutilizado'; exception when check_violation then null; end;
  mg := public.start_minigame('feira', 1, false, false);
  begin perform public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'feira', '{"batata":10}', false, false, false);
    raise exception 'FALHA 10: veículo viajando saiu de novo'; exception when check_violation then null; end;
  -- o jogador não lê o sorteio antes de receber
  select count(*) into n from public.expeditions where user_id = a;
  if n <> 0 then raise exception 'FALHA 11: jogador vê a expedição antes de receber'; end if;
  reset role;
  select * into x from public.expeditions where user_id = a and status = 'travel';
  if x.chance <> 0.95 then raise exception 'FALHA 12: chance na Feira com Perfeita (teto) = %', x.chance; end if;
  if (select durability from public.vehicles where user_id = a and vehicle_id = 'carroca') <> 96 then raise exception 'FALHA 13: desgaste da viagem'; end if;
  if x.cargo_value <> public.exp_cargo_value('{"batata":40,"alface":20}', 'feira', public.game_day(now())) then raise exception 'FALHA 14: valor da carga'; end if;

  -- 4. a viagem volta e ESPERA o clique; o ouro só entra ao Receber
  update public.expeditions set returns_at = (select farm_time from public.farms where user_id = a), chance = 1 where id = x.id;
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if s -> 'expeditions' -> 0 ->> 'status' <> 'back' or (s ->> 'gold')::numeric <> v_gold then raise exception 'FALHA 15: voltou e já pagou (ou não voltou)'; end if;
  s := public.collect_expeditions('carroca');
  if s -> 'collected' -> 0 ->> 'outcome' not in ('crit', 'success') then raise exception 'FALHA 16: chance 100%% e falhou'; end if;
  if (s ->> 'gold')::numeric - v_gold <> (s -> 'collected' -> 0 ->> 'gold')::numeric or (s -> 'collected' -> 0 ->> 'gold')::numeric < x.cargo_value then
    raise exception 'FALHA 17: Receber não pagou a carga'; end if;
  if coalesce(s -> 'collected' -> 0 ->> 'report', '') = '' then raise exception 'FALHA 18: sem relatório'; end if;
  begin perform public.collect_expeditions('carroca'); raise exception 'FALHA 19: recebeu duas vezes'; exception when check_violation then null; end;
  reset role;

  -- 5. falha parcial com seguro (Cidade Vizinha, nível 6): parte volta ao Silo e o seguro devolve a perda acima de 10%
  update public.farms set level = 6 where user_id = a;
  set local role authenticated;
  mg := public.start_minigame('cidade', 1, false, false);
  select gold into v_gold from public.wallets where user_id = a;
  s := public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'cidade', '{"batata":60}', true, false, false);
  if s -> 'minigame' ->> 'result' <> 'failed' then raise exception 'FALHA 20: sem teclas não deu Falhou'; end if;
  reset role;
  select * into x from public.expeditions where user_id = a and status = 'travel';
  if x.insurance <> round(x.cargo_value * 0.024, 2) or v_gold - (select gold from public.wallets where user_id = a) <> x.insurance then raise exception 'FALHA 21: preço do seguro'; end if;
  if abs(x.chance - (0.92 - 0.10)) > 1e-9 then raise exception 'FALHA 22: chance com minigame Falhou = %', x.chance; end if;
  update public.expeditions set returns_at = 0, chance = 0 where id = x.id;
  set local role authenticated;
  s := public.get_farm();
  s := public.collect_expeditions(null);
  reset role;
  select * into x from public.expeditions where id = x.id;
  if x.outcome <> 'fail' or x.loss_frac < 0.15 - 1e-9 or x.loss_frac > 0.35 + 1e-9 then raise exception 'FALHA 23: falha fora da faixa (% %)', x.outcome, x.loss_frac; end if;
  if (x.cargo_back ->> 'batata')::int <> 60 - round(60 * x.loss_frac)::int then raise exception 'FALHA 24: carga que volta'; end if;
  if x.refund <> round((x.loss_frac - 0.10)::numeric * x.cargo_value, 2) then raise exception 'FALHA 25: devolução do seguro'; end if;
  if (s -> 'silo' ->> 'batata')::int <> 460 - 60 + (x.cargo_back ->> 'batata')::int then raise exception 'FALHA 26: carga não voltou ao Silo'; end if;

  -- 6. garantia contra azar: depois de 2 falhas seguidas, +25 pontos
  update public.farms set exp_fail_streak = 2 where user_id = a;
  set local role authenticated;
  mg := public.start_minigame('cidade', 1, false, false);
  s := public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'cidade', '{"batata":10}', false, false, false);
  reset role;
  select * into x from public.expeditions where user_id = a and status = 'travel';
  if abs(x.chance - 0.95) > 1e-9 then raise exception 'FALHA 27: +25 da garantia não entrou (%)', x.chance; end if;
  update public.expeditions set returns_at = 0, chance = 1 where id = x.id;
  set local role authenticated; s := public.get_farm(); s := public.collect_expeditions(null); reset role;
  if (select exp_fail_streak from public.farms where user_id = a) <> 0 then raise exception 'FALHA 28: sucesso não zerou a sequência de falhas'; end if;

  -- 7. robô: intervalos sempre iguais valem no máximo "Concluída" e geram alerta
  set local role authenticated;
  mg := public.start_minigame('feira', 1, false, false);
  select jsonb_agg(jsonb_build_object('k', k, 't', o * 200)) into keys from jsonb_array_elements_text(mg -> 'arrows') with ordinality z(k, o);
  s := public.launch_expedition((mg ->> 'id')::uuid, keys, array['carroca'], 'feira', '{"batata":10}', false, false, true);
  if s -> 'minigame' ->> 'result' <> 'done' then raise exception 'FALHA 29: robô ganhou %', s -> 'minigame' ->> 'result'; end if;
  reset role;
  if not exists (select 1 from public.audit_log where target_user_id = a and action = 'cheat.minigame_robot') then raise exception 'FALHA 30: robô sem alerta'; end if;

  -- 8. repetição: volta e sai sozinha com os mesmos produtos (até 2×), tudo guardado até Receber
  select qty into v_q from public.silo where user_id = a and item_id = 'batata';
  update public.expeditions set returns_at = (select farm_time from public.farms where user_id = a) where user_id = a and status = 'travel';
  set local role authenticated; s := public.get_farm(); reset role;
  select * into x from public.expeditions where user_id = a and status = 'travel';
  if not found or x.seq <> 1 or x.repeat_left <> 1 or not (x.cargo ? 'batata') then raise exception 'FALHA 31: repetição não saiu'; end if;
  if (select qty from public.silo where user_id = a and item_id = 'batata') <> v_q - (x.cargo ->> 'batata')::int then raise exception 'FALHA 32: repetição não tirou do Silo'; end if;
  if (x.cargo ->> 'batata')::int <> 60 then raise exception 'FALHA 33: repetição não encheu até a capacidade (%)', x.cargo; end if;
  update public.expeditions set returns_at = (select farm_time from public.farms where user_id = a) where id = x.id;
  set local role authenticated; s := public.get_farm(); reset role;
  update public.expeditions set returns_at = (select farm_time from public.farms where user_id = a) where user_id = a and status = 'travel';
  set local role authenticated; s := public.get_farm();
  if exists (select 1 from jsonb_array_elements(s -> 'expeditions') e where e ->> 'status' = 'travel') then raise exception 'FALHA 34: repetiu mais de 2 vezes'; end if;
  s := public.collect_expeditions('carroca');
  if jsonb_array_length(s -> 'collected') <> 3 then raise exception 'FALHA 35: Receber trouxe % viagens (esperado 3)', jsonb_array_length(s -> 'collected'); end if;
  reset role;

  -- 9. Gerente conduz: +8 pontos, −10% de duração, sai do trabalho até voltar
  update public.farms set level = 14 where user_id = a;
  insert into public.characters (user_id, class_id, slot) values (a, 'gerente', 'field');
  set local role authenticated;
  mg := public.start_minigame('feira', 1, true, false);
  if (mg ->> 'limit_ms')::int <> 7000 then raise exception 'FALHA 36: Gerente não deu +1 s'; end if;
  s := public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'feira', '{"batata":10}', false, true, false);
  if not exists (select 1 from jsonb_array_elements(s -> 'characters') c where c ->> 'class_id' = 'gerente' and (c ->> 'leading')::boolean and not (c ->> 'active')::boolean) then
    raise exception 'FALHA 37: Gerente conduzindo continua trabalhando'; end if;
  begin mg := public.start_minigame('feira', 1, true, false);
    perform public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'feira', '{"batata":10}', false, true, false);
    raise exception 'FALHA 38: Gerente conduziu duas expedições'; exception when check_violation then null; end;
  reset role;
  select * into x from public.expeditions where user_id = a and status = 'travel';
  if not x.led or abs((x.returns_at - x.started_at) - 0.5 * 1.3 * 0.9 * 3600) > 1 then raise exception 'FALHA 39: duração com o Gerente'; end if;
  if abs(x.chance - least(0.95, 0.97 + (-10 + 8) / 100.0)) > 1e-9 then raise exception 'FALHA 40: +8 do Gerente (%)', x.chance; end if;
  update public.expeditions set returns_at = 0 where id = x.id;
  set local role authenticated; s := public.get_farm(); s := public.collect_expeditions(null); reset role;
  if (select leading_id from public.characters where user_id = a and class_id = 'gerente') is not null then raise exception 'FALHA 41: Gerente não voltou'; end if;

  -- 10. comprar o Carro e mandar comboio (1 minigame com +2 setas e +1,5 s)
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.buy_vehicle('carro');
  if (s ->> 'gold')::numeric <> v_gold - 33000 then raise exception 'FALHA 42: preço do Carro'; end if;
  mg := public.start_minigame('cidade', 2, false, false);
  if jsonb_array_length(mg -> 'arrows') <> 7 or (mg ->> 'limit_ms')::int <> 7500 then raise exception 'FALHA 43: minigame do comboio %', mg; end if;
  s := public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carro', 'carroca'], 'cidade', '{"batata":150}', false, false, false);
  reset role;
  if (select count(distinct convoy_id) from public.expeditions where user_id = a and status = 'travel') <> 1
     or (select sum((cargo ->> 'batata')::int) from public.expeditions where user_id = a and status = 'travel') <> 150
     or (select (cargo ->> 'batata')::int from public.expeditions where user_id = a and status = 'travel' and vehicle_id = 'carro') <> 120 then
    raise exception 'FALHA 44: comboio dividiu a carga errado'; end if;
  update public.expeditions set returns_at = 0 where user_id = a and status = 'travel';
  set local role authenticated; s := public.get_farm(); s := public.collect_expeditions(null); reset role;

  -- 11. reforma: 3 Kits Incomuns viram 1 Raro; Incomum pede 1 kit + 30% do preço de referência; capacidade ×1,2
  insert into public.inventory (user_id, item_id, qty) values (a, 'kit:uncommon', 4);
  set local role authenticated;
  s := public.merge_items('kit:uncommon');
  if (s -> 'inventory' ->> 'kit:uncommon')::int <> 1 or (s -> 'inventory' ->> 'kit:rare')::int <> 1 then raise exception 'FALHA 45: juntar kits'; end if;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.refurbish_vehicle('carroca');
  if (s ->> 'gold')::numeric <> v_gold - 9900 or (s -> 'inventory' ->> 'kit:uncommon') is not null then raise exception 'FALHA 46: preço ou kit da reforma'; end if;
  mg := public.start_minigame('feira', 1, false, false);
  begin perform public.launch_expedition((mg ->> 'id')::uuid, '[]', array['carroca'], 'feira', '{"batata":10}', false, false, false);
    raise exception 'FALHA 47: veículo saiu durante a reforma'; exception when check_violation then null; end;
  reset role;
  update public.vehicles set refurb_until = 0 where user_id = a and vehicle_id = 'carroca';
  set local role authenticated; s := public.get_farm(); reset role;
  if (select rarity from public.vehicles where user_id = a and vehicle_id = 'carroca') <> 'uncommon'
     or public.exp_capacity((select v from public.vehicles v where user_id = a and vehicle_id = 'carroca'), null) <> 72 then raise exception 'FALHA 48: reforma não terminou'; end if;

  -- 12. conserto proporcional; vestimenta equipada (Chapéu Raro: +15 × 1,6 de energia máxima)
  update public.vehicles set durability = 50 where user_id = a and vehicle_id = 'carroca';
  insert into public.inventory (user_id, item_id, qty) values (a, 'cloth_hat:rare', 1);
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.repair_vehicle('carroca');
  if (s ->> 'gold')::numeric <> v_gold - 33000 * 0.1 * 0.5 then raise exception 'FALHA 49: preço do conserto'; end if;
  s := public.equip_item('agricultor', 'cloth', 'cloth_hat:rare');
  if (select (c ->> 'energy_max')::numeric from jsonb_array_elements(s -> 'characters') c where c ->> 'class_id' = 'agricultor') <> 124 then raise exception 'FALHA 50: chapéu não deu energia'; end if;
  begin perform public.equip_item('agricultor', 'amulet', 'cloth_hat:rare'); raise exception 'FALHA 51: chapéu no espaço do amuleto'; exception when check_violation then null; end;
  s := public.equip_item('agricultor', 'cloth', null);
  if (s -> 'inventory' ->> 'cloth_hat:rare')::int <> 1 then raise exception 'FALHA 52: tirar o item não devolveu'; end if;
  reset role;

  -- 13. demanda: produto da demanda vale +20% na rota
  select products into v_dem from public.daily_demand where day = public.game_day(now()) and route_id = 'feira';
  if public.exp_cargo_value(jsonb_build_object(v_dem[1], 10), 'feira', public.game_day(now())) <> round(10 * public.item_price(v_dem[1]) * 1.2, 2) then
    raise exception 'FALHA 53: demanda sem +20%%'; end if;

  -- 14. segurança: B não vê os veículos de A; ninguém escreve direto; funções internas e do admin fechadas
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.vehicles where user_id = a;
  if n <> 0 then raise exception 'FALHA 54: B vê os veículos de A'; end if;
  begin update public.vehicles set rarity = 'mythic' where user_id = b; get diagnostics n = row_count; if n > 0 then raise exception 'FALHA 55: jogador mudou a raridade'; end if;
  exception when insufficient_privilege then null; end;
  begin perform public.exp_resolve(gen_random_uuid(), '{}'); raise exception 'FALHA 56: jogador chamou função interna';
  exception when insufficient_privilege then null; end;
  begin select count(*) into n from public.minigames; raise exception 'FALHA 57: jogador leu as setas guardadas';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_finish_expeditions(a, 'quero testar'); raise exception 'FALHA 58: jogador usou ferramenta do admin';
  exception when insufficient_privilege then null; end;
  begin perform public.collect_expeditions(null); raise exception 'FALHA 59: B recebeu sem ter viagem';
  exception when check_violation then null; end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
