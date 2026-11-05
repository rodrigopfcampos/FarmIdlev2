-- Testes da reformulação v3, parte R3: Lago (igual ao Galinheiro: vagas, peixe escolhido, raridade; Pescador especialista)
-- e árvore de habilidades da conta.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); s jsonb; t double precision; q int; exp_q double precision; fx jsonb; c public.characters; d jsonb; v_g numeric;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r3-' || a || '@exemplo.test', '{"nickname":"R3a","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.advance_farm(a);
  update public.farms set level = 15 where user_id = a;

  update public.wallets set gold = 1e9 where user_id = a;
  d := public.animal_def('tilapia');
  -- 1. sem Lago não compra peixe
  set local role authenticated;
  begin perform public.buy_animal('lago', 1, 'tilapia'); raise exception 'FALHA 1: peixe sem Lago';
  exception when check_violation then null; end;
  reset role;

  -- 2. Lago pronto: 4 vagas; peixe liberado pelo nível, raridade sorteada na compra; o preço vem do animal
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (a, 'L', 0, 9);
  perform public.advance_farm(a);
  if public.house_slots(a, 'lago') <> 4 then raise exception 'FALHA 2: vagas do Lago %', public.house_slots(a, 'lago'); end if;
  if public.item_price('fish_tilapia') <> (d -> 'product' ->> 'fair_price_per_unit')::numeric then raise exception 'FALHA 3: preço do peixe'; end if;
  select gold into v_g from public.wallets where user_id = a;
  set local role authenticated;
  s := public.buy_animal('lago', 1, 'tilapia');
  begin perform public.buy_animal('lago', 2, 'truta'); raise exception 'FALHA 4: Truta antes do nível';
  exception when check_violation then null; end;
  begin perform public.buy_animal('lago', 5, 'tilapia'); raise exception 'FALHA 4b: 5ª vaga no Lago de 4';
  exception when check_violation then null; end;
  begin perform public.buy_animal('galinheiro', 1, 'tilapia'); raise exception 'FALHA 4c: peixe no Galinheiro';
  exception when check_violation then null; end;
  reset role;
  if (select rarity from public.animals where user_id = a and house_id = 'lago' and slot = 1) is null
     or not exists (select 1 from public.audit_log where target_user_id = a and action = 'animal.bought' and data ->> 'house' = 'lago') then raise exception 'FALHA 5: compra sem raridade'; end if;
  if abs(v_g - (select gold from public.wallets where user_id = a) - (d ->> 'buy_cost')::numeric
         - round((d ->> 'feed_cost_per_day')::numeric * (d ->> 'produce_every_minutes')::numeric / 1440, 2)) > 0.02 then raise exception 'FALHA 6: preço + ração do 1º ciclo'; end if;

  -- 3. pronto: o clique coleta a 100% (o peixe vai para o Silo) e começa o próximo ciclo
  select farm_time into t from public.farms where user_id = a;
  update public.animals set rarity = 'common', ready_at = t - 1 where user_id = a and house_id = 'lago';
  delete from public.silo where user_id = a;
  set local role authenticated;
  s := public.tend_farm('L');
  reset role;
  if (select qty from public.silo where user_id = a and item_id = 'fish_tilapia') <> 1 then raise exception 'FALHA 7: clique não pescou %', (select qty from public.silo where user_id = a and item_id = 'fish_tilapia'); end if;
  if (select ready_at from public.animals where user_id = a and house_id = 'lago') <= t then raise exception 'FALHA 8: não recomeçou o ciclo'; end if;
  if not (s -> 'animals') @> jsonb_build_array(jsonb_build_object('house_id', 'lago')) then raise exception 'FALHA 9: estado sem o peixe'; end if;

  -- 4. carta Pesca Lendária: +14% no peixe; o Rebanho não vale no Lago
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'pesca', 'legendary', 'admin');
  set local role authenticated;
  perform public.equip_card((select serial from public.cards where user_id = a and card_id = 'pesca'));
  reset role;
  fx := public.team_fx(a);
  if abs((fx ->> 'fishing')::numeric - 0.14) > 0.001 then raise exception 'FALHA 10: carta Pesca %', fx ->> 'fishing'; end if;
  -- 5. equipe: 60% sem o Pescador em campo; 100% com ele (o especialista do Lago)
  delete from public.silo where user_id = a;
  update public.animals set rarity = 'mythic', ready_at = t - 1 where user_id = a and house_id = 'lago';
  for q in 1 .. 40 loop perform public.animal_collect(a, 'lago', 1, t, fx || '{"pescador": false, "legendary_fish": 0}', true); end loop;
  exp_q := 40 * public.rarity_mult('mythic') * 1.14 * 0.6;
  if abs((select qty from public.silo where user_id = a and item_id = 'fish_tilapia') - exp_q) > 8 then raise exception 'FALHA 11: equipe sem Pescador rendeu % (esperado ~%)', (select qty from public.silo where user_id = a and item_id = 'fish_tilapia'), round(exp_q::numeric, 1); end if;
  delete from public.silo where user_id = a;
  for q in 1 .. 40 loop perform public.animal_collect(a, 'lago', 1, t, fx || '{"pescador": true, "legendary_fish": 0}', true); end loop;
  exp_q := 40 * public.rarity_mult('mythic') * 1.14;
  if abs((select qty from public.silo where user_id = a and item_id = 'fish_tilapia') - exp_q) > 10 then raise exception 'FALHA 12: equipe com Pescador rendeu %', (select qty from public.silo where user_id = a and item_id = 'fish_tilapia'); end if;
  -- 6. a coleta do Lago gasta a carta Pesca (1/4 de uso por peixe) e conta como peixe
  if (select uses_left from public.card_buffs where user_id = a and card_id = 'pesca') >= 4 then raise exception 'FALHA 13: Lago não gastou a carta Pesca'; end if;
  -- 7. o Pescador: nível 30, Vara de Pescar, especialista do Lago; o Campo tem 4 vagas
  if (public.class_def('pescador') ->> 'unlock_level')::int <> 30 or (public.config_get('characters') ->> 'field_slots')::int <> 4 then raise exception 'FALHA 14: Pescador ou vagas de campo'; end if;
  if public.config_get('animals') -> 'rules' -> 'collector_efficiency' -> 'specialist_by_house' ->> 'lago' <> 'pescador' then raise exception 'FALHA 15: especialista do Lago'; end if;
  update public.farms set level = 30 where user_id = a;
  set local role authenticated;
  s := public.hire('pescador');
  reset role;
  if not exists (select 1 from public.tools where user_id = a and class_id = 'pescador') then raise exception 'FALHA 16: Pescador sem a Vara'; end if;
  update public.farms set level = 15 where user_id = a;
  delete from public.characters where user_id = a and class_id = 'pescador';

  -- 8. Árvore de Passivas: Folha de Pagamento (salários), Manutenção (consertos), Mestre Pescador; o Lago não dá mais +10% nas aves
  update public.farms set account_skills = '{"folha": 5, "manutencao": 5, "mestre_pescador": 5}' where user_id = a;
  select * into c from public.characters where user_id = a limit 1;
  c.class_id := 'rancheira';
  if abs(public.salary_of(a, c) - round(public.ref_income(15) * (public.config_get('characters') -> 'salary' ->> 'share_of_R')::numeric
       * (1 + (public.config_get('characters') -> 'salary' ->> 'per_character_level')::numeric * c.level) * 0.85, 2)) > 0.02 then raise exception 'FALHA 16: Salários −15%%'; end if;
  fx := public.team_fx(a);
  if abs((fx ->> 'repair_cut')::numeric - 0.25) > 0.001 or abs((fx ->> 'legendary_fish')::numeric - 0.15) > 0.001 or abs((fx ->> 'tool_wear_cut')::numeric - 0.15) > 0.001 then
    raise exception 'FALHA 17: passivas %', fx; end if;
  if (public.config_get('animals') -> 'rules' -> 'lake_bonus' ->> 'bird_production')::numeric <> 0 then raise exception 'FALHA 18: Lago ainda dá +10%% nas aves'; end if;
  if public.account_points(a) <> 14 then raise exception 'FALHA 19: pontos no nível 15 = %', public.account_points(a); end if;
  if (public.farm_state(a) -> 'account_tree' ->> 'spent')::int <> 15 then raise exception 'FALHA 20: estado da árvore'; end if;

  raise exception 'TESTES_OK';
end $$;
