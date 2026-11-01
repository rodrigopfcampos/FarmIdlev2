-- Testes da Árvore de Passivas: caminho (A abre B e C, B ou C com 3 abre D, Ultimate com 15 no ramo e custo 5) e efeitos novos.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare a uuid := gen_random_uuid(); s jsonb; fx jsonb; t double precision; n int; q int; c public.characters; en jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pas-' || a || '@exemplo.test', '{"nickname":"Pas","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.advance_farm(a);
  update public.farms set level = 50 where user_id = a;

  -- 1. caminho do Comércio
  set local role authenticated;
  begin perform public.account_skill_add('logistica'); raise exception 'FALHA 1: B sem A';
  exception when check_violation then null; end;
  s := public.account_skill_add('labia');
  s := public.account_skill_add('logistica'); s := public.account_skill_add('logistica');
  begin perform public.account_skill_add('rotas'); raise exception 'FALHA 2: D com B em 2';
  exception when check_violation then null; end;
  s := public.account_skill_add('logistica');
  s := public.account_skill_add('rotas');
  begin perform public.account_skill_add('contrabando'); raise exception 'FALHA 3: Ultimate com menos de 15 no ramo';
  exception when check_violation then null; end;
  for n in 1 .. 4 loop s := public.account_skill_add('labia'); end loop;
  for n in 1 .. 2 loop s := public.account_skill_add('logistica'); end loop;
  for n in 1 .. 4 loop s := public.account_skill_add('rotas'); end loop;
  -- 5 + 5 + 5 = 15 no ramo: Ultimate liberada, custa 5
  s := public.account_skill_add('contrabando');
  begin perform public.account_skill_add('contrabando'); raise exception 'FALHA 4: Ultimate passou de 1';
  exception when check_violation then null; end;
  reset role;
  if public.account_spent(a) <> 20 or (s -> 'account_tree' ->> 'spent')::int <> 20 then raise exception 'FALHA 5: pontos gastos %', public.account_spent(a); end if;
  fx := public.team_fx(a);
  if (fx -> 'exp_card' ->> 'cargo')::numeric <> 25 then raise exception 'FALHA 6: Contrabando %', fx -> 'exp_card'; end if;
  if abs((fx ->> 'stall_ratio')::numeric - 0.75) > 0.001 then raise exception 'FALHA 7: Lábia %', fx ->> 'stall_ratio'; end if;

  -- 2. sem pontos: 49 no nível 50
  update public.farms set account_skills = '{"labia":5,"logistica":5,"manutencao":5,"rotas":5,"contrabando":1,"mao_verde":5,"carinho_animal":5,"mestre_pescador":4,"cafe_forte":5,"sinergia":5}' where user_id = a;
  if public.account_spent(a) <> 49 then raise exception 'FALHA 8a: gasto %', public.account_spent(a); end if;
  set local role authenticated;
  begin perform public.account_skill_add('terra_fertil'); raise exception 'FALHA 8: passou de 49 pontos';
  exception when check_violation then null; end;
  reset role;

  -- 3. Natureza: Mão Verde 100% faz a semente nascer pronta; Mutação dobra
  update public.farms set account_skills = '{"mao_verde": 100}' where user_id = a;
  fx := public.team_fx(a);
  select farm_time into t from public.farms where user_id = a;
  perform public.plant_plot(a, 'A1-1', 'batata', t, fx);
  if (select ready_at from public.plots where user_id = a and plot_id = 'A1-1') <> t then raise exception 'FALHA 9: Mão Verde'; end if;
  update public.farms set account_skills = '{"mutacao": 10, "carinho_animal": 5}' where user_id = a;
  fx := public.team_fx(a);
  if (fx ->> 'mutation')::numeric <> 1 then raise exception 'FALHA 10: Mutação %', fx ->> 'mutation'; end if;
  if abs((fx ->> 'feed_discount')::numeric - 0.2) > 0.001 then raise exception 'FALHA 11: ração do Carinho Animal %', fx ->> 'feed_discount'; end if;

  -- 4. Resistência: Fôlego de Ferro abaixo de 30% e Segundo Fôlego
  update public.farms set account_skills = '{"folego_ferro": 5, "segundo_folego": 1}' where user_id = a;
  fx := public.team_fx(a);
  select * into c from public.characters where user_id = a and class_id = 'agricultor';
  c.energy := 100; en := public.char_energy(c, fx); t := (en ->> 'use')::double precision;
  c.energy := 10; en := public.char_energy(c, fx);
  if abs((en ->> 'use')::double precision - t * 0.7) > 0.001 then raise exception 'FALHA 12: Fôlego de Ferro % × %', en ->> 'use', t; end if;
  if abs((fx ->> 'revive_pct')::numeric - 0.3) > 0.001 then raise exception 'FALHA 13: Segundo Fôlego'; end if;
  update public.characters set energy = 0.01, slot = 'field', parked = false, revive_day = null where user_id = a and class_id = 'agricultor';
  perform public.tick_team(a, 1, 1, fx);
  if (select energy from public.characters where user_id = a and class_id = 'agricultor') < 29 or (select parked from public.characters where user_id = a and class_id = 'agricultor') then
    raise exception 'FALHA 14: Segundo Fôlego não reviveu (%)', (select energy from public.characters where user_id = a and class_id = 'agricultor'); end if;

  raise exception 'TESTES_OK';
end $$;
