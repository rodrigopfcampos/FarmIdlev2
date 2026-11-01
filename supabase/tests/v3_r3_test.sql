-- Testes da reformulação v3, parte R3: pesca no Lago e árvore de habilidades da conta.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); s jsonb; t double precision; q int; exp_q double precision; fx jsonb; c public.characters;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r3-' || a || '@exemplo.test', '{"nickname":"R3a","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.advance_farm(a);
  update public.farms set level = 15 where user_id = a;

  -- 1. sem Lago não pesca
  set local role authenticated;
  begin perform public.collect_fish(); raise exception 'FALHA 1: pescou sem Lago';
  exception when check_violation then null; end;
  reset role;

  -- 2. Lago pronto: a rede começa a encher
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (a, 'L', 0, 9);
  perform public.advance_farm(a);
  if (select fish_t from public.farms where user_id = a) is null then raise exception 'FALHA 2: rede não começou'; end if;
  if public.item_price('fish_truta') <> 390 then raise exception 'FALHA 3: preço do peixe'; end if;
  if public.fish_species(15) ->> 'id' <> 'fish_truta' or public.fish_species(40) ->> 'id' <> 'fish_esturjao' then raise exception 'FALHA 4: espécie por nível'; end if;

  -- 3. 3 ciclos prontos: clique recolhe a Truta (8% de R ÷ 12 por ciclo) e a rede segue do ponto certo
  select farm_time into t from public.farms where user_id = a;
  update public.farms set fish_t = t - 3 * 7200 - 100 where user_id = a;
  if public.fish_cycles(a, t) <> 3 then raise exception 'FALHA 5: ciclos %', public.fish_cycles(a, t); end if;
  set local role authenticated;
  s := public.collect_fish();
  reset role;
  exp_q := public.ref_income(15) * 0.08 / 12 * 3 / 390;
  q := (select qty from public.silo where user_id = a and item_id = 'fish_truta');
  if abs(q - exp_q) > 1 then raise exception 'FALHA 6: % trutas (esperado ~%)', q, round(exp_q::numeric, 1); end if;
  if abs((select fish_t from public.farms where user_id = a) - (t - 100)) > 1 then raise exception 'FALHA 7: rede não guardou o resto do ciclo'; end if;
  if s -> 'fishing' is null or (s -> 'fishing' ->> 'cycles')::int <> 0 then raise exception 'FALHA 8: estado da pesca %', s -> 'fishing'; end if;
  set local role authenticated;
  begin perform public.collect_fish(); raise exception 'FALHA 9: rede vazia recolheu';
  exception when check_violation then null; end;
  reset role;

  -- 4. rede cheia para em 4 ciclos (8 h); recolher recomeça do zero
  update public.farms set fish_t = t - 20 * 7200 where user_id = a;
  if public.fish_cycles(a, t) <> 4 then raise exception 'FALHA 10: rede passou de 4 ciclos'; end if;
  delete from public.silo where user_id = a;
  perform public.fish_collect(a, t, public.team_fx(a), false);
  if abs((select fish_t from public.farms where user_id = a) - t) > 0.01 then raise exception 'FALHA 11: rede cheia não recomeçou'; end if;
  exp_q := public.ref_income(15) * 0.08 / 12 * 4 / 390;
  if abs((select qty from public.silo where user_id = a and item_id = 'fish_truta') - exp_q) > 1 then raise exception 'FALHA 12: rede cheia rendeu errado'; end if;

  -- 5. Vara de Pescar Lendária: +14% na pesca; equipe rende 60%
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'pesca', 'legendary', 'admin');
  set local role authenticated;
  perform public.equip_card((select serial from public.cards where user_id = a and card_id = 'pesca'));
  reset role;
  fx := public.team_fx(a);
  if abs((fx ->> 'fishing')::numeric - 0.14) > 0.001 then raise exception 'FALHA 13: Vara de Pescar %', fx ->> 'fishing'; end if;
  delete from public.silo where user_id = a;
  update public.farms set fish_t = t - 4 * 7200 where user_id = a;
  perform public.fish_collect(a, t, fx, true);
  exp_q := public.ref_income(15) * 0.08 / 12 * 4 * 1.14 * 0.6 / 390;
  if abs((select qty from public.silo where user_id = a and item_id = 'fish_truta') - exp_q) > 1 then raise exception 'FALHA 14: equipe com a Vara rendeu %', (select qty from public.silo where user_id = a and item_id = 'fish_truta'); end if;

  -- 6. fora do jogo a equipe recolhe a rede cheia
  update public.farms set fish_t = farm_time - 8 * 3600, synced_at = now() - interval '30 minutes', last_activity_at = now() where user_id = a;
  perform public.advance_farm(a);
  if not exists (select 1 from public.audit_log where target_user_id = a and action = 'fish.collect' and (data ->> 'team')::boolean) then raise exception 'FALHA 15: equipe não recolheu a rede'; end if;

  -- 7. Árvore de Passivas: Folha de Pagamento (salários), Manutenção (consertos), Mestre Pescador; o Lago não dá mais +10% nas aves
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
