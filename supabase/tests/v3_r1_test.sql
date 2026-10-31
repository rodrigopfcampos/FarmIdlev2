-- Testes da reformulação v3, parte R1: mapa novo (sem A9; Celeiro no C1 e Galinheiro no C2) e zerar a fazenda.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); adm uuid := gen_random_uuid(); s jsonb; n_ledger int; v_start numeric;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v3-a-' || a || '@exemplo.test', '{"nickname":"V3a","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v3-b-' || b || '@exemplo.test', '{"nickname":"V3b","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v3-adm-' || adm || '@exemplo.test', '{"nickname":"V3adm","birth_date":"1990-01-01"}', now(), now());
  -- amizade com outro jogador (aponta para a linha da fazenda): zerar não pode quebrar nem apagar
  insert into public.friendships (user_a, user_b, requested_by, status) values (least(a, b), greatest(a, b), a, 'accepted');
  update public.profiles set is_admin = true where id = adm;
  v_start := (public.config_get('levels') ->> 'starting_gold')::numeric;

  -- 1. mapa: 29 lotes, sem A9; C1 é o Celeiro e C2 o Galinheiro
  if jsonb_array_length(public.config_get('map_rules') -> 'lots') <> 29 then raise exception 'FALHA 1: mapa com % lotes', jsonb_array_length(public.config_get('map_rules') -> 'lots'); end if;
  if exists (select 1 from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = 'A9') then raise exception 'FALHA 2: A9 ainda existe'; end if;
  if (select x ->> 'type' from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = 'C1') <> 'pasto_celeiro' then raise exception 'FALHA 3: C1 não é o Celeiro'; end if;
  if jsonb_array_length(public.config_get('lots') -> 'purchases') <> 28 then raise exception 'FALHA 4: tabela com % compras', jsonb_array_length(public.config_get('lots') -> 'purchases'); end if;

  -- 2. comprar o A9 é recusado
  perform public.ledger_post(a, 1000000, 'test_grant');
  update public.farms set level = 40 where user_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  begin perform public.buy_lot('A9'); raise exception 'FALHA 5: comprou o A9';
  exception when check_violation or no_data_found or invalid_parameter_value then null; end;
  -- 3. o Celeiro (C1) libera a casa das vacas
  s := public.buy_lot('A3');
  s := public.buy_lot('C1');
  reset role;
  if not exists (select 1 from public.owned_lots where user_id = a and lot_id = 'C1') then raise exception 'FALHA 6: C1 não comprado'; end if;
  update public.owned_lots set ready_at = 0 where user_id = a;
  set local role authenticated;
  s := public.get_farm();
  if (s -> 'houses' -> 'celeiro' ->> 'lot') <> 'C1' or not (s -> 'houses' -> 'celeiro' ->> 'owned')::boolean then raise exception 'FALHA 7: casa do C1 = %', s -> 'houses'; end if;
  reset role;

  -- 4. jogador não zera a própria fazenda; o admin zera (com justificativa)
  set local role authenticated;
  begin perform public.reset_farm(a, 'teste'); raise exception 'FALHA 8: jogador chamou reset_farm';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_reset_farm(a, 'teste'); raise exception 'FALHA 9: jogador zerou pelo painel';
  exception when insufficient_privilege then null; end;
  reset role;
  select count(*) into n_ledger from public.ledger where user_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin perform public.admin_reset_farm(a, ''); raise exception 'FALHA 10: zerou sem justificativa';
  exception when check_violation then null; end;
  s := public.admin_reset_farm(a, 'mapa novo da v3');
  reset role;

  -- 5. depois de zerar: só o A1, nível 1, ouro inicial, ledger maior (nada apagado) e batendo com a carteira
  if (select array_agg(lot_id) from public.owned_lots where user_id = a) <> array['A1'] then raise exception 'FALHA 11: lotes %', (select array_agg(lot_id) from public.owned_lots where user_id = a); end if;
  if (select level from public.farms where user_id = a) <> 1 then raise exception 'FALHA 12: nível não voltou a 1'; end if;
  if (select gold from public.wallets where user_id = a) <> v_start then raise exception 'FALHA 13: ouro %', (select gold from public.wallets where user_id = a); end if;
  if (select count(*) from public.ledger where user_id = a) <> n_ledger + 1 then raise exception 'FALHA 14: ledger com % lançamentos (esperado %)', (select count(*) from public.ledger where user_id = a), n_ledger + 1; end if;
  if (select sum(amount) from public.ledger where user_id = a) <> (select gold from public.wallets where user_id = a) then raise exception 'FALHA 15: ledger × carteira'; end if;
  if (select count(*) from public.plots where user_id = a) <> 8 then raise exception 'FALHA 16: canteiros %', (select count(*) from public.plots where user_id = a); end if;
  if not exists (select 1 from public.audit_log where target_user_id = a and action = 'admin.reset_farm') then raise exception 'FALHA 17: sem auditoria'; end if;
  if not exists (select 1 from public.friendships where user_a = least(a, b) and user_b = greatest(a, b)) then raise exception 'FALHA 19: a amizade sumiu'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  if (s ->> 'level')::int <> 1 or jsonb_array_length(s -> 'lots') <> 1 then raise exception 'FALHA 18: estado depois de zerar %', s -> 'lots'; end if;
  reset role;

  raise exception 'TESTES_OK';
end $$;
