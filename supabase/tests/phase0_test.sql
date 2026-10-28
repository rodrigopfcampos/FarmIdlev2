-- Testes da fase 0 (rodar no projeto de TESTE). Tudo é desfeito no fim:
-- o resultado esperado é o erro "TESTES_OK"; qualquer outro erro "FALHA ..." diz o que quebrou.
-- fase 6: clima desligado (este teste não depende da hora do dia)
select set_config('vif.weather', 'off', false);
-- fase 7: missões desligadas (os prêmios mudariam as contas deste teste)
select set_config('vif.missions', 'off', false);
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  n int;
  g numeric;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'teste-a-' || a || '@exemplo.test',
     '{"nickname":"Teste A","birth_date":"1990-05-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'teste-b-' || b || '@exemplo.test',
     '{"nickname":"x","birth_date":"2000-01-31"}', now(), now());

  -- 0. menor de idade ou sem data de nascimento: conta recusada
  begin
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'menor@exemplo.test',
       json_build_object('nickname', 'Menor', 'birth_date', (current_date - interval '17 years')::date)::jsonb, now(), now());
    raise exception 'FALHA 0a: conta de menor aceita';
  exception when check_violation then null;
  end;
  begin
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'semdata@exemplo.test',
       '{"nickname":"Sem Data"}', now(), now());
    raise exception 'FALHA 0b: conta sem data de nascimento aceita';
  exception when check_violation then null;
  end;

  -- 1. conta nova: perfil, carteira, ouro inicial da config, auditoria
  select gold into g from public.wallets where user_id = a;
  if g is distinct from 2000 then raise exception 'FALHA 1: ouro inicial % (esperado 2000)', g; end if;
  select count(*) into n from public.ledger where user_id = a and reason = 'starting_gold';
  if n <> 1 then raise exception 'FALHA 2: % lançamentos de ouro inicial', n; end if;
  select count(*) into n from public.audit_log where target_user_id = a and action = 'account.created';
  if n <> 1 then raise exception 'FALHA 3: conta nova sem auditoria'; end if;
  if (select nickname from public.profiles where id = b) not like 'Fazendeiro%' then raise exception 'FALHA 4: apelido curto aceito'; end if;
  if (select birth_date from public.profiles where id = a) <> date '1990-05-01' then raise exception 'FALHA 5: data de nascimento'; end if;

  -- 2. ledger_post: idempotência, saldo nunca negativo, saldo = soma do ledger
  perform public.ledger_post(a, -500, 'test_spend', '{}', 'k1');
  perform public.ledger_post(a, -500, 'test_spend', '{}', 'k1');
  if (select gold from public.wallets where user_id = a) <> 1500 then raise exception 'FALHA 6: idempotência'; end if;
  begin
    perform public.ledger_post(a, -999999, 'test_spend');
    raise exception 'FALHA 7: saldo negativo aceito';
  exception when check_violation then null;
  end;
  if (select sum(amount) from public.ledger where user_id = a) <> (select gold from public.wallets where user_id = a) then
    raise exception 'FALHA 8: carteira diferente da soma do ledger';
  end if;

  -- 3. ledger e audit_log são imutáveis, até para o dono do banco
  begin
    update public.ledger set amount = 1 where user_id = a;
    raise exception 'FALHA 9: ledger alterado';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.ledger where user_id = a;
    raise exception 'FALHA 10: ledger apagado';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.audit_log where target_user_id = a;
    raise exception 'FALHA 11: audit_log apagado';
  exception when insufficient_privilege then null;
  end;

  -- 4. como o jogador A: vê só o que é dele e não escreve nada direto
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.ledger;
  if n <> 2 then raise exception 'FALHA 12: jogador vê % lançamentos (esperado 2)', n; end if;
  select count(*) into n from public.profiles;
  if n <> 1 then raise exception 'FALHA 13: jogador vê % perfis', n; end if;
  select count(*) into n from public.wallets where user_id = b;
  if n <> 0 then raise exception 'FALHA 14: jogador vê a carteira de outro'; end if;
  begin
    select count(*) into n from public.audit_log;
    raise exception 'FALHA 15: jogador lê o audit_log';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.ledger (user_id, amount, balance_after, reason) values (a, 1000000, 1000000, 'cheat');
    raise exception 'FALHA 16: jogador escreve no ledger';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.wallets set gold = 999999 where user_id = a;
    raise exception 'FALHA 17: jogador muda a carteira';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.ledger_post(a, 1000000, 'cheat');
    raise exception 'FALHA 18: jogador chama ledger_post';
  exception when insufficient_privilege then null;
  end;
  select count(*) into n from public.game_config;
  if n < 1 then raise exception 'FALHA 19: config não é legível'; end if;
  reset role;

  -- 5. visitante sem login não vê dados de ninguém
  set local role anon;
  select count(*) into n from public.ledger;
  if n <> 0 then raise exception 'FALHA 20: visitante vê o ledger'; end if;
  select count(*) into n from public.profiles;
  if n <> 0 then raise exception 'FALHA 21: visitante vê perfis'; end if;
  reset role;

  raise exception 'TESTES_OK';
end $$;
