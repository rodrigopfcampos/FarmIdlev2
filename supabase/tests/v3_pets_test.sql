-- Testes dos pets v3: chegam sozinhos pelo nível, valem todos juntos, achado a cada X horas, carinho sobe o nível.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); s jsonb; v_gold numeric; v_t double precision; v_n int; d jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pet-a-' || a || '@exemplo.test', '{"nickname":"PetA","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pet-b-' || b || '@exemplo.test', '{"nickname":"PetB","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- 1. nível 1: nenhum pet; nível 12: Cachorro e Gato chegam sozinhos; nível 20: os 3
  set local role authenticated; s := public.get_farm(); reset role;
  if jsonb_array_length(s -> 'pets') <> 0 then raise exception 'FALHA 1: pet no nível 1'; end if;
  update public.farms set level = 12 where user_id = a;
  set local role authenticated; s := public.get_farm(); reset role;
  if jsonb_array_length(s -> 'pets') <> 2 then raise exception 'FALHA 2: no nível 12 vieram % pets', jsonb_array_length(s -> 'pets'); end if;
  update public.farms set level = 20 where user_id = a;
  set local role authenticated; s := public.get_farm(); reset role;
  if jsonb_array_length(s -> 'pets') <> 3 then raise exception 'FALHA 3: no nível 20 vieram % pets', jsonb_array_length(s -> 'pets'); end if;

  -- 2. os três valem juntos (nível 1 = 40%): Cachorro +1,6 ponto, Papagaio +1,6% nas vendas, Gato +16% de descanso
  if abs(public.pet_factor(a, 'cachorro') - 0.4) > 1e-9 then raise exception 'FALHA 4: fator do nível 1'; end if;
  if abs((public.team_fx(a) ->> 'sales_gold')::numeric - 0.016) > 1e-9 then raise exception 'FALHA 5: Papagaio nas vendas %', public.team_fx(a) ->> 'sales_gold'; end if;
  if abs((public.team_fx(a) ->> 'dog_recover')::numeric - 0.04) > 1e-9 then raise exception 'FALHA 6: Cachorro na carga perdida %', public.team_fx(a) ->> 'dog_recover'; end if;

  -- 3. achado ainda não pronto é recusado; pronto, o Papagaio traz moedas (0,4% de R × 40%) e a contagem recomeça
  set local role authenticated;
  begin perform public.collect_pet('papagaio'); raise exception 'FALHA 7: recolheu achado antes da hora';
  exception when check_violation then null; end;
  reset role;
  update public.pets set find_t = find_t - 6 * 3600 - 1 where user_id = a; -- todos prontos (o maior é 6 h)
  select gold into v_gold from public.wallets where user_id = a;
  select farm_time into v_t from public.farms where user_id = a;
  set local role authenticated; s := public.collect_pet('papagaio'); reset role;
  if (s -> 'pet_find' ->> 'gold')::numeric <> round(public.ref_income(20) * 0.004 * 0.4, 2) or (s ->> 'gold')::numeric <> v_gold + (s -> 'pet_find' ->> 'gold')::numeric then
    raise exception 'FALHA 8: moedas do Papagaio %', s -> 'pet_find'; end if;
  if (select find_t from public.pets where user_id = a and pet_id = 'papagaio') < v_t then raise exception 'FALHA 9: contagem não recomeçou'; end if;
  set local role authenticated;
  begin perform public.collect_pet('papagaio'); raise exception 'FALHA 10: recolheu 2 vezes';
  exception when check_violation then null; end;
  reset role;

  -- 4. Gato: energia para toda a equipe (15 × 40% = 6)
  update public.characters set energy = 10, parked = true where user_id = a;
  set local role authenticated; s := public.collect_pet('gato'); reset role;
  if exists (select 1 from public.characters where user_id = a and abs(energy - 16) > 1e-6) then raise exception 'FALHA 11: energia do Gato'; end if;

  -- 5. Cachorro: baú com ouro; com a chance de carta em 100% vem uma carta
  update public.game_config set data = jsonb_set(data, '{pets,list,0,find,card_chance}', '1') where name = 'characters';
  select count(*) into v_n from public.cards where user_id = a;
  set local role authenticated; s := public.collect_pet('cachorro'); reset role;
  if (s -> 'pet_find' ->> 'gold')::numeric <= 0 or s -> 'pet_find' -> 'card' is null
     or (select count(*) from public.cards where user_id = a and origin = 'pet') <> 1 then raise exception 'FALHA 12: baú do Cachorro %', s -> 'pet_find'; end if;

  -- 6. carinho: 1 por dia por pet; com afinidade 30 o pet chega ao nível 5 (100%)
  set local role authenticated;
  s := public.care_pet('gato');
  begin perform public.care_pet('gato'); raise exception 'FALHA 13: 2 carinhos no mesmo dia';
  exception when check_violation then null; end;
  s := public.care_pet('cachorro');
  reset role;
  update public.pets set affinity = 30 where user_id = a and pet_id = 'papagaio';
  if public.pet_level(a, 'papagaio') <> 5 or abs((public.team_fx(a) ->> 'sales_gold')::numeric - 0.04) > 1e-9 then raise exception 'FALHA 14: Papagaio nível 5'; end if;

  -- 7. adoção, troca e vínculo acabaram; o ledger bate
  set local role authenticated;
  begin perform public.set_active_pet('gato'); raise exception 'FALHA 15: troca de pet ainda existe';
  exception when undefined_function then null; end; -- v3: a função foi removida
  begin perform public.link_pet('rancheira'); raise exception 'FALHA 16: vínculo ainda existe';
  exception when undefined_function then null; end; -- v3: a função foi removida
  reset role;
  if (select sum(amount) from public.ledger where user_id = a) <> (select gold from public.wallets where user_id = a) then raise exception 'FALHA 17: ledger × carteira'; end if;

  -- 8. segurança: B não vê nem recolhe os pets de A; funções internas fechadas
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if (select count(*) from public.pets where user_id = a) <> 0 then raise exception 'FALHA 18: B vê os pets de A'; end if;
  begin perform public.collect_pet('cachorro'); raise exception 'FALHA 19: B recolheu sem ter pet';
  exception when check_violation then null; end;
  begin perform public.pets_unlock(a, 0); raise exception 'FALHA 20: jogador chamou função interna';
  exception when insufficient_privilege then null; end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
