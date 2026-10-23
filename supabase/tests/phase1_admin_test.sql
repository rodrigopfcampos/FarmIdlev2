-- Testes do painel do admin (projeto de TESTE). Esperado: erro "TESTES_OK".
do $$
declare
  adm uuid := gen_random_uuid();
  pl uuid := gen_random_uuid();
  n int;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm-' || adm || '@exemplo.test', '{"nickname":"Admin Teste","birth_date":"1990-01-01"}', now(), now()),
    (pl, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pl-' || pl || '@exemplo.test', '{"nickname":"Jogador Teste","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;

  -- 1. jogador comum não usa o painel
  perform set_config('request.jwt.claims', json_build_object('sub', pl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    perform * from public.admin_search_players('');
    raise exception 'FALHA 1: jogador comum buscou jogadores';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- 2. admin sem 2FA (aal1) também não
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  set local role authenticated;
  if (public.admin_whoami() ->> 'is_admin')::boolean is not true then raise exception 'FALHA 2: whoami'; end if;
  begin
    perform * from public.admin_player_ledger(pl);
    raise exception 'FALHA 3: admin sem 2FA viu o ledger';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- 3. admin com 2FA busca, vê ledger, auditoria e fazenda; tudo fica registrado
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  select count(*) into n from public.admin_search_players('Jogador Teste');
  if n <> 1 then raise exception 'FALHA 4: busca achou %', n; end if;
  select count(*) into n from public.admin_player_ledger(pl);
  if n <> 1 then raise exception 'FALHA 5: ledger com % linhas', n; end if;
  select count(*) into n from public.admin_player_audit(pl);
  if n < 1 then raise exception 'FALHA 6: auditoria vazia'; end if;
  if (public.admin_player_farm(pl) ->> 'nickname') <> 'Jogador Teste' then raise exception 'FALHA 7: fazenda'; end if;
  reset role;
  select count(*) into n from public.audit_log where actor_id = adm and action like 'admin.%';
  if n <> 4 then raise exception 'FALHA 8: % ações do admin registradas (esperado 4)', n; end if;

  -- 4. o próprio jogador não consegue virar admin
  perform set_config('request.jwt.claims', json_build_object('sub', pl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    update public.profiles set is_admin = true where id = pl;
    raise exception 'FALHA 9: jogador virou admin';
  exception when insufficient_privilege then null;
  end;
  reset role;

  raise exception 'TESTES_OK';
end $$;
