-- Testes da fase 8b: Encomenda da Vila (pedidos, meta, doação de ouro e produto, pontos, prêmios, títulos)
-- e Estrelas da Vila (XP depois do 50, compra de pacote e semente com limite por semana).
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);  -- os prêmios das missões não entram nas contas de ouro
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); adm uuid := gen_random_uuid();
  s jsonb; o1 bigint; o2 bigint; v_gold numeric; v_r numeric; v_pts numeric; it text; n int; per numeric; v_cards int;
begin
  -- encerra Encomendas abertas de outros testes/jogadores (tudo é desfeito no fim)
  update public.village_orders set ends_at = now() - interval '1 second' where ends_at > now();
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8b-a-' || a || '@exemplo.test', '{"nickname":"Vila8a","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8b-b-' || b || '@exemplo.test', '{"nickname":"Vila8b","birth_date":"1990-01-01"}', now(), now()),
    (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8b-c-' || c || '@exemplo.test', '{"nickname":"Vila8c","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8b-adm-' || adm || '@exemplo.test', '{"nickname":"Vila8adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;
  perform public.ledger_post(a, 1000000, 'test_grant');
  perform public.ledger_post(b, 1000000, 'test_grant');
  perform public.ledger_post(c, 1000000, 'test_grant');

  -- 1. a Encomenda da semana: 3 pedidos (1 por faixa de nível), meta pelo número de ativos, termina na segunda 00:00 UTC
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_village();
  reset role;
  o1 := (s -> 'order' ->> 'id')::bigint;
  if jsonb_array_length(s -> 'order' -> 'items') <> 3 then raise exception 'FALHA 1: pedidos %', s -> 'order'; end if;
  if (s -> 'order' ->> 'goal')::numeric < 16 then raise exception 'FALHA 2: meta %', s -> 'order' ->> 'goal'; end if;
  if extract(isodow from ((s -> 'order' ->> 'ends_at')::timestamptz at time zone 'UTC')) <> 1 then raise exception 'FALHA 3: não termina na segunda'; end if;
  if (public.village_order_current()).id <> o1 then raise exception 'FALHA 4: abriu outra Encomenda na mesma semana'; end if;
  update public.village_orders set goal = 30 where id = o1;

  -- 2. doar ouro: some da carteira; pontos = ouro ÷ (renda do nível ÷ 24)
  select gold into v_gold from public.wallets where user_id = a;
  v_r := public.ref_income(1) / 24;
  set local role authenticated;
  s := public.village_donate(null, round(v_r * 20, 2));
  reset role;
  if (select gold from public.wallets where user_id = a) <> v_gold - round(v_r * 20, 2) then raise exception 'FALHA 5: ouro não saiu'; end if;
  if abs((s -> 'mine' ->> 'points')::numeric - 20) > 0.01 then raise exception 'FALHA 6: 20 h de renda deram % pontos', s -> 'mine' ->> 'points'; end if;
  if not exists (select 1 from public.ledger where user_id = a and reason = 'village_donation') then raise exception 'FALHA 7: sem ledger'; end if;

  -- 3. doar produto: preço da Feira; o pedido da semana vale 1,5×; não doa mais do que tem
  select items[1] into it from public.village_orders where id = o1;
  insert into public.silo (user_id, item_id, qty) values (b, it, 1000) on conflict (user_id, item_id) do update set qty = 1000;
  insert into public.silo (user_id, item_id, qty) values (b, 'cenoura', 1000) on conflict (user_id, item_id) do update set qty = 1000;
  per := round(2 * public.item_price(it) / v_r * 1.5, 4);          -- o que o pedido deve dar
  v_gold := round(10 * public.item_price('cenoura') / v_r, 4);     -- o que 10 cenouras devem dar (sem bônus)
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.village_donate(it, 2);
  v_pts := (s -> 'mine' ->> 'points')::numeric;
  if abs(v_pts - per) > 0.01 then raise exception 'FALHA 8: pedido deu % pontos (esperado %)', v_pts, per; end if;
  if it <> 'cenoura' then
    s := public.village_donate('cenoura', 10);
    if abs((s -> 'mine' ->> 'points')::numeric - v_pts - v_gold) > 0.01 then raise exception 'FALHA 9: produto comum'; end if;
  end if;
  begin perform public.village_donate(it, 100000); raise exception 'FALHA 10: doou mais do que tinha';
  exception when check_violation then null; end;
  begin perform public.village_donate(it, 1.5); raise exception 'FALHA 11: meia unidade';
  exception when check_violation then null; end;
  reset role;
  if (select qty from public.silo where user_id = b and item_id = it) <> 998 then raise exception 'FALHA 12: Silo não baixou'; end if;
  -- b chega a 5 pontos com ouro; c doa só 1 ponto (abaixo do mínimo de 2)
  set local role authenticated;
  s := public.village_donate(null, round(v_r * greatest(0, 5 - (s -> 'mine' ->> 'points')::numeric) + 1, 2));
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.village_donate(null, round(v_r, 2));
  reset role;

  -- 4. fim da semana com a meta batida (20 + 5 + 1 ≥ 26 com a meta em 25): todos que passaram do mínimo ganham 1 carta; o top 10% ganha +1
  update public.village_orders set goal = 25, ends_at = now() - interval '1 second' where id = o1;
  perform public.village_settle(a); perform public.village_settle(b); perform public.village_settle(c);
  if (select cards from public.village_rewards where order_id = o1 and user_id = a) <> 2 then raise exception 'FALHA 13: top não ganhou 2 cartas'; end if;
  if (select cards from public.village_rewards where order_id = o1 and user_id = b) <> 1 then raise exception 'FALHA 14: participante não ganhou 1 carta'; end if;
  if (select cards from public.village_rewards where order_id = o1 and user_id = c) <> 0 then raise exception 'FALHA 15: abaixo do mínimo ganhou carta'; end if;
  if (select count(*) from public.cards where user_id = a and origin = 'encomenda') <> 2 then raise exception 'FALHA 16: cartas não chegaram'; end if;
  perform public.village_settle(a);
  if (select count(*) from public.cards where user_id = a and origin = 'encomenda') <> 2 then raise exception 'FALHA 17: prêmio pago duas vezes'; end if;
  if public.village_title(a) <> 'Herói da Vila' or public.village_title(b) <> 'Ajudante da Vila' or public.village_title(c) is not null then
    raise exception 'FALHA 18: títulos % % %', public.village_title(a), public.village_title(b), public.village_title(c); end if;
  if public.player_card(a) ->> 'title' <> 'Herói da Vila' then raise exception 'FALHA 19: título fora do cartão do jogador'; end if;

  -- 5. semana seguinte com a meta não batida: só o top ganha a carta dele
  o2 := (public.village_order_current()).id;
  if o2 = o1 then raise exception 'FALHA 20: não abriu a Encomenda seguinte'; end if;
  update public.village_orders set goal = 100000 where id = o2;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.village_donate(null, round(v_r * 3, 2));
  reset role;
  update public.village_orders set ends_at = now() - interval '1 second' where id = o2;
  perform public.village_settle(a);
  if (select cards from public.village_rewards where order_id = o2 and user_id = a) <> 1 then raise exception 'FALHA 21: top sem meta'; end if;

  -- 6. Estrelas: depois do 50, cada 10% do XP do nível 49 vira 1 Estrela
  per := (public.config_get('levels') -> 'levels' -> 48 ->> 'xp_to_next')::numeric * 0.1;
  update public.farms set level = 50, xp = 0, stars = 0 where user_id = a;
  perform public.add_xp(a, per * 2.5);
  if (select stars from public.farms where user_id = a) <> 2 or abs((select xp from public.farms where user_id = a) - per * 0.5) > 1 then
    raise exception 'FALHA 22: estrelas % xp %', (select stars from public.farms where user_id = a), (select xp from public.farms where user_id = a); end if;
  -- quem passa do 49 para o 50 já leva o resto para as Estrelas
  update public.farms set level = 49, xp = 0, stars = 0 where user_id = b;
  perform public.add_xp(b, (public.config_get('levels') -> 'levels' -> 48 ->> 'xp_to_next')::numeric + per);
  if (select level from public.farms where user_id = b) <> 50 or (select stars from public.farms where user_id = b) <> 1 then raise exception 'FALHA 23: virada do 49 para o 50'; end if;

  -- 7. loja: pacote = 5 Estrelas + 1 R de ouro (2 por semana); semente Rara = 2 Estrelas + 0,2 R (5 por semana); sem Mítico
  update public.farms set stars = 30 where user_id = a;
  perform public.ledger_post(a, 100000000, 'test_grant');
  select gold into v_gold from public.wallets where user_id = a;
  select count(*) into v_cards from public.cards where user_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.star_buy('pack');
  if (s -> 'stars' ->> 'stars')::int <> 25 then raise exception 'FALHA 24: estrelas depois do pacote %', s -> 'stars'; end if;
  s := public.star_buy('pack');
  begin perform public.star_buy('pack'); raise exception 'FALHA 25: 3º pacote na semana';
  exception when check_violation then null; end;
  s := public.star_buy('seed', 'alface', 'rare');
  begin perform public.star_buy('seed', 'alface', 'mythic'); raise exception 'FALHA 26: semente Mítica';
  exception when check_violation then null; end;
  begin perform public.star_buy('seed', 'pedra', 'rare'); raise exception 'FALHA 27: cultivo inexistente';
  exception when check_violation then null; end;
  reset role;
  if (select count(*) from public.cards where user_id = a) <> v_cards + 2 or not exists (select 1 from public.cards where user_id = a and origin = 'estrelas') then raise exception 'FALHA 28: pacote não deu carta'; end if;
  if coalesce((select qty from public.inventory where user_id = a and item_id = 'seed:alface:rare'), 0) <> 1 then raise exception 'FALHA 29: semente não chegou'; end if;
  if abs(v_gold - (select gold from public.wallets where user_id = a) - round(public.ref_income(50) * 2.2, 2)) > 0.05 then raise exception 'FALHA 30: ouro da loja'; end if;
  if (select stars from public.farms where user_id = a) <> 18 then raise exception 'FALHA 31: estrelas no fim %', (select stars from public.farms where user_id = a); end if;
  -- abaixo do 50 não compra
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  update public.farms set stars = 10 where user_id = c;
  set local role authenticated;
  begin perform public.star_buy('pack'); raise exception 'FALHA 32: comprou abaixo do 50';
  exception when check_violation then null; end;

  -- 8. painel: só admin encerra a Encomenda e dá Estrelas; fica registrado
  begin perform public.admin_grant_stars(c, 5, 'teste do jogador'); raise exception 'FALHA 33: jogador se deu estrelas';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_grant_stars(a, 5, 'teste do painel');
  s := public.admin_close_village('teste do painel');
  reset role;
  if (select stars from public.farms where user_id = a) <> 23 then raise exception 'FALHA 34: painel não deu estrelas'; end if;
  if not exists (select 1 from public.audit_log where action = 'admin.close_village' and actor_id = adm) then raise exception 'FALHA 35: sem registro'; end if;

  raise exception 'TESTES_OK';
end $$;
