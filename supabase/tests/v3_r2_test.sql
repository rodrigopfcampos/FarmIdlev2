-- Testes da reformulação v3, parte R2: as 20 cartas (efeitos novos, mão por nível, veículo pela carta).
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); s jsonb; fx jsonb; n bigint; k text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r2-a-' || a || '@exemplo.test', '{"nickname":"R2a","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- 1. a config tem as 20 cartas e a mão cresce com o nível (3, 4 no 15, 5 no 30)
  if jsonb_array_length(public.config_get('cards') -> 'cards') <> 20 then raise exception 'FALHA 1: % cartas', jsonb_array_length(public.config_get('cards') -> 'cards'); end if;
  if public.hand_slots(1) <> 3 or public.hand_slots(14) <> 3 or public.hand_slots(15) <> 4 or public.hand_slots(30) <> 5 or public.hand_slots(50) <> 5 then raise exception 'FALHA 2: mão por nível'; end if;
  -- toda carta nova é sorteável e tem efeito em todas as raridades
  for k in select x ->> 'id' from jsonb_array_elements(public.config_get('cards') -> 'cards') x loop
    if (select count(*) from jsonb_object_keys(public.card_def(k) -> 'buff_effects')) <> 5 then raise exception 'FALHA 3: % sem as 5 raridades', k; end if;
  end loop;

  -- 2. efeitos novos (Lendárias): Cesta, Luvas, Engrenagem, Enxada, Forcado, Martelo, Balança, Prancheta, Pesca
  update public.farms set level = 30 where user_id = a;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'cesta', 'legendary', 'admin'), (a, 'luvas', 'legendary', 'admin'), (a, 'engrenagem', 'legendary', 'admin'),
    (a, 'enxada', 'legendary', 'admin'), (a, 'forcado', 'legendary', 'admin');
  set local role authenticated;
  for n in select serial from public.cards where user_id = a order by serial loop perform public.equip_card(n); end loop;
  reset role;
  fx := public.team_fx(a);
  if abs((fx ->> 'yield')::numeric - 0.09) > 0.001 then raise exception 'FALHA 4: Cesta %', fx ->> 'yield'; end if;
  if abs((fx ->> 'team_capacity')::numeric - 0.18) > 0.001 then raise exception 'FALHA 5: Luvas + Engrenagem %', fx ->> 'team_capacity'; end if;
  if abs((fx ->> 'vehicle_wear')::numeric + 0.09) > 0.001 then raise exception 'FALHA 6: Engrenagem no desgaste %', fx ->> 'vehicle_wear'; end if;
  if abs((fx ->> 'crop_work_cut')::numeric - 0.09) > 0.001 or abs((fx ->> 'ao_work_cut')::numeric - 0.09) > 0.001 then raise exception 'FALHA 7: Enxada/Forcado %', fx; end if;
  -- 6ª carta numa mão de 5 é recusada
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'martelo', 'legendary', 'admin') returning serial into n;
  set local role authenticated;
  begin perform public.equip_card(n); raise exception 'FALHA 8: 6ª carta na mão';
  exception when check_violation then null; end;
  reset role;
  delete from public.card_buffs where user_id = a;
  update public.cards set state = 'binder' where user_id = a;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'balanca', 'legendary', 'admin'), (a, 'prancheta', 'legendary', 'admin'), (a, 'pesca', 'legendary', 'admin');
  set local role authenticated;
  for n in select serial from public.cards where user_id = a and card_id in ('martelo', 'balanca', 'prancheta', 'pesca') order by serial loop perform public.equip_card(n); end loop;
  reset role;
  fx := public.team_fx(a);
  if abs((fx ->> 'tool_wear_cut')::numeric - 0.17) > 0.001 or abs((fx ->> 'w_speed_cleanup')::numeric - 0.17) > 0.001 then raise exception 'FALHA 9: Martelo %', fx; end if;
  if abs((fx ->> 'sales_gold')::numeric - 0.07) > 0.001 then raise exception 'FALHA 10: Balança %', fx ->> 'sales_gold'; end if;
  if (fx ->> 'exp_success')::numeric < 5 or abs((fx ->> 'exp_duration')::numeric + 0.10) > 0.001 then raise exception 'FALHA 11: Prancheta % / %', fx ->> 'exp_success', fx ->> 'exp_duration'; end if;
  if abs((fx ->> 'fishing')::numeric - 0.14) > 0.001 then raise exception 'FALHA 12: Pesca %', fx ->> 'fishing'; end if;
  delete from public.card_buffs where user_id = a;

  -- 3. veículos liberam por nível (30: Carro, Off-Road, 4x4 e Caminhão); a carta de Veículo Mítica dá +35% de carga e lucro e +5 de jackpot
  set local role authenticated; s := public.get_farm(); reset role;
  if (select count(*) from public.vehicles where user_id = a) <> 5 then raise exception 'FALHA 13: veículos no nível 30 = %', (select count(*) from public.vehicles where user_id = a); end if;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'veiculo', 'mythic', 'admin') returning serial into n;
  set local role authenticated;
  s := public.equip_card(n);
  reset role;
  fx := public.team_fx(a);
  if (fx -> 'exp_card' ->> 'cargo')::numeric <> 35 or (fx -> 'exp_card' ->> 'profit')::numeric <> 35 or (fx -> 'exp_card' ->> 'crit_pts')::numeric <> 5 then raise exception 'FALHA 15: bônus do Veículo %', fx -> 'exp_card'; end if;
  update public.card_buffs set ends_at = now() - interval '1 second' where user_id = a and card_id = 'veiculo';
  perform public.buffs_expire(a, now());
  if (select state from public.cards where serial = n) <> 'used' then raise exception 'FALHA 18: Veículo Mítico gasto não sumiu'; end if;
  if (select count(*) from public.vehicles where user_id = a) <> 5 then raise exception 'FALHA 19: veículos sumiram com a carta'; end if;

  raise exception 'TESTES_OK';
end $$;
