-- Testes da fase 3: personagens, energia, salário, rodízio, lanches, habilidades, ferramentas,
-- funções de apoio (Comerciante, Gerente, Botânica), sementes raras, pets e segurança (projeto de TESTE).
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  s jsonb; n int; v_gold numeric; v_e double precision; v_r double precision; v_r2 double precision; v_q int; v_cost numeric;
  r3 numeric := public.ref_income(3);
  r10 numeric := public.ref_income(10);
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f3-a-' || a || '@exemplo.test', '{"nickname":"Fase3 A","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f3-b-' || b || '@exemplo.test', '{"nickname":"Fase3 B","birth_date":"1990-01-01"}', now(), now());

  -- 1. conta nova: Agricultor no campo, energia cheia, ferramenta inteira
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  if jsonb_array_length(s -> 'characters') <> 1 or s -> 'characters' -> 0 ->> 'class_id' <> 'agricultor' or s -> 'characters' -> 0 ->> 'slot' <> 'field'
    then raise exception 'FALHA 1: conta nova sem o Agricultor no campo'; end if;
  if (s -> 'characters' -> 0 ->> 'energy')::numeric <> 100 or (s -> 'characters' -> 0 ->> 'durability')::numeric <> 100 then raise exception 'FALHA 2: energia ou ferramenta não começam cheias'; end if;
  if abs((s ->> 'labor_per_hour')::numeric - 2.67) > 0.001 then raise exception 'FALHA 3: trabalho por hora % (esperado 2,67)', s ->> 'labor_per_hour'; end if;
  -- contratar acima do nível é recusado
  begin perform public.hire('rancheira'); raise exception 'FALHA 4: contratou acima do nível';
  exception when check_violation then null; end;
  reset role;

  -- 2. fora do jogo o Agricultor trabalha, gasta energia e desgasta a Enxada; com 0 fica parado
  update public.plots set crop_id = 'alface' where user_id = a;
  update public.farms set synced_at = synced_at - interval '8 hours', last_activity_at = last_activity_at - interval '8 hours' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  reset role;
  select energy into v_e from public.characters where user_id = a and class_id = 'agricultor';
  if v_e >= 50 then raise exception 'FALHA 5: em 8 h de trabalho a energia ficou em %', v_e; end if;
  if (select durability from public.tools where user_id = a and class_id = 'agricultor') >= 100 then raise exception 'FALHA 6: a Enxada não desgastou'; end if;
  if (select work_hours from public.characters where user_id = a and class_id = 'agricultor') <= 0
     and (select level from public.characters where user_id = a and class_id = 'agricultor') = 1 then raise exception 'FALHA 7: personagem não ganhou horas'; end if;
  update public.characters set energy = 0, parked = true where user_id = a and class_id = 'agricultor';
  set local role authenticated;
  s := public.get_farm();
  if (s ->> 'labor_per_hour')::numeric <> 0 then raise exception 'FALHA 8: parado sem energia ainda trabalha'; end if;
  reset role;
  -- descansa no slot e volta com 60
  update public.farms set synced_at = synced_at - interval '3 hours', last_activity_at = now() where user_id = a;
  update public.plots set crop_id = null where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'characters' -> 0 ->> 'parked')::boolean or (s -> 'characters' -> 0 ->> 'energy')::numeric < 40 then raise exception 'FALHA 9: não descansou até voltar ao trabalho (energia %)', s -> 'characters' -> 0 ->> 'energy'; end if;
  reset role;

  -- 3. contratar a Rancheira no nível 3: custa 1,5 × R(3) e entra no campo
  update public.farms set level = 3 where user_id = a;
  perform public.ledger_post(a, 100000, 'test_grant');
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.hire('rancheira');
  if (s ->> 'gold')::numeric <> v_gold - 1.5 * r3 then raise exception 'FALHA 10: contratação cobrou %', v_gold - (s ->> 'gold')::numeric; end if;
  if (select slot from public.characters where user_id = a and class_id = 'rancheira') <> 'field' then raise exception 'FALHA 11: contratada não foi para o campo'; end if;
  begin perform public.hire('rancheira'); raise exception 'FALHA 12: contratou duas vezes';
  exception when check_violation then null; end;
  reset role;

  -- 4. salário à meia-noite; sem ouro vira dívida (Desmotivado = metade do trabalho); pagar volta ao normal
  update public.farms set last_payday = last_payday - 1 where user_id = a;
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (s ->> 'gold')::numeric >= v_gold then raise exception 'FALHA 13: salário não foi cobrado'; end if;
  select (x ->> 'rate')::double precision into v_r from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'rancheira';
  reset role;
  perform public.ledger_post(a, -(select gold from public.wallets where user_id = a), 'test_spend');
  update public.farms set last_payday = last_payday - 1 where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  select (x ->> 'rate')::double precision into v_r2 from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'rancheira';
  if (select debt from public.characters where user_id = a and class_id = 'rancheira') <= 0 then raise exception 'FALHA 14: sem ouro, o salário não virou dívida'; end if;
  if abs(v_r2 - v_r * 0.5) > 0.001 then raise exception 'FALHA 15: Desmotivado trabalha % (esperado metade de %)', v_r2, v_r; end if;
  begin perform public.pay_salaries(); raise exception 'FALHA 16: pagou sem ouro';
  exception when check_violation then null; end;
  reset role;
  -- 3 dias devendo: para de trabalhar
  update public.farms set last_payday = last_payday - 2 where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (select (x ->> 'active')::boolean from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'rancheira') then raise exception 'FALHA 17: com 3 dias devendo ainda trabalha'; end if;
  reset role;
  perform public.ledger_post(a, 1000000, 'test_grant');
  set local role authenticated;
  s := public.pay_salaries();
  select (x ->> 'rate')::double precision into v_r2 from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'rancheira';
  if abs(v_r2 - v_r) > 0.001 or not (select (x ->> 'active')::boolean from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'rancheira')
    then raise exception 'FALHA 18: pagar não voltou ao normal'; end if;
  if (select sum(amount) from public.ledger where user_id = a) <> (s ->> 'gold')::numeric then raise exception 'FALHA 19: ledger diferente da carteira'; end if;
  reset role;

  -- 5. Ferreiro: limpeza no tempo da tabela (sem ele, o dobro)
  update public.farms set level = 6 where user_id = a;
  set local role authenticated;
  s := public.hire('ferreiro');
  s := public.buy_lot('A3');
  if abs(((select ready_at from public.owned_lots where user_id = a and lot_id = 'A3') - (s ->> 'farm_time')::double precision) - (60 + 12 * 1) * 60) > 1
    then raise exception 'FALHA 20: limpeza com Ferreiro fora da tabela'; end if;
  reset role;

  -- 6. rodízio com 4: quem chega a 10 sai do campo e entra quem tem 60 ou mais
  update public.farms set level = 10 where user_id = a;
  set local role authenticated;
  s := public.hire('comerciante');
  if (select slot from public.characters where user_id = a and class_id = 'comerciante') <> 'bench' then raise exception 'FALHA 21: 4º personagem não foi para o banco'; end if;
  reset role;
  update public.characters set energy = 5 where user_id = a and class_id = 'ferreiro';
  update public.characters set energy = 100 where user_id = a and class_id = 'comerciante';
  update public.farms set synced_at = synced_at - interval '10 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (select slot from public.characters where user_id = a and class_id = 'ferreiro') <> 'bench'
     or (select slot from public.characters where user_id = a and class_id = 'comerciante') <> 'field' then raise exception 'FALHA 22: rodízio não trocou'; end if;
  -- campo cheio: não entra um 4º
  begin perform public.set_slot('ferreiro', 'field'); raise exception 'FALHA 23: 4 no campo';
  exception when check_violation then null; end;

  -- 7. Comerciante em campo: Barraca a 71% (Madeira) e venda automática dos itens marcados
  if abs((s -> 'fx' ->> 'stall_ratio')::numeric - 0.71) > 1e-9 then raise exception 'FALHA 24: Barraca a % com o Comerciante', s -> 'fx' ->> 'stall_ratio'; end if;
  reset role;
  insert into public.silo (user_id, item_id, qty) values (a, 'batata', 10) on conflict (user_id, item_id) do update set qty = 10;
  set local role authenticated;
  s := public.set_auto_sell('batata', true);
  reset role;
  update public.farms set synced_at = synced_at - interval '10 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if coalesce((s -> 'silo' ->> 'batata')::int, 0) <> 0 then raise exception 'FALHA 25: Comerciante não vendeu sozinho'; end if;
  reset role;
  if not exists (select 1 from public.ledger where user_id = a and reason = 'auto_sale') then raise exception 'FALHA 26: venda automática fora do ledger'; end if;

  -- 8. lanches: comprar, pôr no espaço e o personagem come sozinho abaixo de 15%
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.buy_snack('snack_coffee', 3);
  if abs(v_gold - (s ->> 'gold')::numeric - 3 * round(r10 * 0.016, 2)) > 0.01 then raise exception 'FALHA 27: preço do lanche errado'; end if;
  s := public.equip_snack('agricultor', 'snack_coffee');
  if (select snack_qty from public.characters where user_id = a and class_id = 'agricultor') <> 3 then raise exception 'FALHA 28: lanche não foi para o espaço'; end if;
  reset role;
  update public.characters set energy = 10, parked = false where user_id = a and class_id = 'agricultor';
  update public.farms set synced_at = synced_at - interval '10 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  reset role;
  if (select snack_qty from public.characters where user_id = a and class_id = 'agricultor') <> 2 then raise exception 'FALHA 29: não comeu o lanche'; end if;
  if (select energy from public.characters where user_id = a and class_id = 'agricultor') < 45 then raise exception 'FALHA 30: lanche não deu energia'; end if;

  -- 9. habilidades: pontos = nível − 1; Mestria só com os dois nós cheios; reset grátis 1×/semana
  update public.characters set level = 12 where user_id = a and class_id = 'agricultor';
  set local role authenticated;
  for n in 1 .. 5 loop s := public.skill_add('agricultor', 'cultivo.a'); end loop;
  begin perform public.skill_add('agricultor', 'cultivo.m'); raise exception 'FALHA 31: Mestria sem os nós cheios';
  exception when check_violation then null; end;
  for n in 1 .. 5 loop s := public.skill_add('agricultor', 'cultivo.b'); end loop;
  s := public.skill_add('agricultor', 'cultivo.m');
  begin perform public.skill_add('agricultor', 'cultivo.m'); raise exception 'FALHA 32: gastou mais pontos que o nível dá';
  exception when check_violation then null; end;
  select (x ->> 'rate')::double precision into v_r from jsonb_array_elements(s -> 'characters') x where x ->> 'class_id' = 'agricultor';
  if abs(v_r - 2.67 * 1.30) > 0.01 then raise exception 'FALHA 33: +6%% × 5 de capacidade não apareceu (%)', v_r; end if;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.skill_reset('agricultor');
  if (s ->> 'gold')::numeric <> v_gold then raise exception 'FALHA 34: 1º reset da semana não foi grátis'; end if;
  s := public.skill_add('agricultor', 'economia.a');
  s := public.skill_reset('agricultor');
  if (s ->> 'gold')::numeric <> v_gold - round(r10 * 0.5, 2) then raise exception 'FALHA 35: 2º reset não custou 50%% de R'; end if;
  begin perform public.skill_add('agricultor', 'xyz.a'); raise exception 'FALHA 36: nó inexistente aceito';
  exception when check_violation then null; end;

  -- 10. ferramentas: consertar a Enxada e melhorar o Martelo do Ferreiro
  select gold into v_gold from public.wallets where user_id = a;
  s := public.repair_tool('agricultor');
  if (s ->> 'gold')::numeric <> v_gold - 100 then raise exception 'FALHA 37: conserto da Madeira não custou 100'; end if;
  s := public.upgrade_tool('ferreiro');
  if (s -> 'tools' ->> 'ferreiro') <> 'copper' then raise exception 'FALHA 38: Martelo não melhorou'; end if;
  reset role;

  -- 11. Semente Rara: Mítica rende ×3 (Alface 3 → 9) e não cobra semente
  insert into public.inventory (user_id, item_id, qty) values (a, 'seed:alface:mythic', 1);
  update public.plots set state = 'empty', planted_crop_id = null, ready_at = null, planted_at = null, crop_id = null where user_id = a and plot_id = 'A1-1';
  delete from public.silo where user_id = a and item_id = 'alface';
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.plant_rare_seed('A1-1', 'alface', 'mythic');
  if (s ->> 'gold')::numeric <> v_gold then raise exception 'FALHA 39: semente rara cobrou ouro'; end if;
  begin perform public.plant_rare_seed('A1-2', 'alface', 'mythic'); raise exception 'FALHA 40: plantou semente que não tem';
  exception when check_violation then null; end;
  reset role;
  update public.plots set ready_at = 0 where user_id = a and plot_id = 'A1-1';
  update public.characters set energy = 0, parked = true where user_id = a; -- ninguém trabalha: só o clique colhe
  set local role authenticated;
  s := public.tend_farm('A1-1');
  if (s -> 'silo' ->> 'alface')::int <> 9 then raise exception 'FALHA 41: Alface Mítica rendeu %', s -> 'silo' ->> 'alface'; end if;
  reset role;

  -- 12. pets: o 1º é grátis no nível 5, o 2º custa 1 dia de renda; 1 carinho por dia; troca com espera
  set local role authenticated;
  select gold into v_gold from public.wallets where user_id = a;
  s := public.adopt_pet('gato');
  if (s ->> 'gold')::numeric <> v_gold or not (s -> 'pets' -> 0 ->> 'active')::boolean then raise exception 'FALHA 42: 1º pet não foi grátis e ativo'; end if;
  s := public.adopt_pet('papagaio');
  if (s ->> 'gold')::numeric <> v_gold - r10 then raise exception 'FALHA 43: 2º pet não custou 1 dia de renda'; end if;
  s := public.care_pet('gato');
  begin perform public.care_pet('gato'); raise exception 'FALHA 44: 2 carinhos no mesmo dia';
  exception when check_violation then null; end;
  if (select energy from public.characters where user_id = a and class_id = 'agricultor') <> 5 then raise exception 'FALHA 45: carinho não deu +5 de energia ao vinculado'; end if;
  s := public.set_active_pet('papagaio');
  begin perform public.set_active_pet('gato'); raise exception 'FALHA 46: trocou o pet sem esperar 7 dias';
  exception when check_violation then null; end;
  reset role;
  update public.pets set affinity = 30 where user_id = a and pet_id = 'papagaio';
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'pet' ->> 'level')::int <> 5 or abs((s -> 'fx' ->> 'sales_gold')::numeric - 0.04) > 1e-9 then raise exception 'FALHA 47: Papagaio nível 5 não dá +4%% nas vendas'; end if;
  reset role;

  -- 13. Gerente em campo: paga a dívida sozinho e reduz o gasto de energia da equipe
  update public.farms set level = 14 where user_id = a;
  perform public.ledger_post(a, 1000000, 'test_grant');
  set local role authenticated;
  s := public.set_slot('comerciante', 'bench');
  s := public.hire('gerente');
  reset role;
  update public.characters set debt = 50, unpaid_days = 1 where user_id = a and class_id = 'rancheira';
  update public.farms set synced_at = synced_at - interval '10 minutes' where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (select debt from public.characters where user_id = a and class_id = 'rancheira') <> 0 then raise exception 'FALHA 48: Gerente não pagou a dívida'; end if;
  if abs((s -> 'fx' ->> 'gerente_cut')::numeric - 0.05) > 1e-9 then raise exception 'FALHA 49: Gerente de Madeira não corta 5%% da energia'; end if;

  -- 14. segurança: B não vê personagens nem pets de A; ninguém escreve direto; funções internas fechadas
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.characters where user_id = a;
  if n <> 0 then raise exception 'FALHA 50: B vê os personagens de A'; end if;
  select count(*) into n from public.pets where user_id = a;
  if n <> 0 then raise exception 'FALHA 51: B vê os pets de A'; end if;
  begin update public.characters set energy = 100 where user_id = b; raise exception 'FALHA 52: jogador mudou a energia direto';
  exception when insufficient_privilege then null; end;
  begin perform public.process_payday(b, now()); raise exception 'FALHA 53: jogador chamou função interna';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_force_payday(a, 'quero testar'); raise exception 'FALHA 54: jogador usou ferramenta do admin';
  exception when insufficient_privilege then null; end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
