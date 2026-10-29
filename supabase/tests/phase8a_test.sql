-- Testes da fase 8a: busca, amizade, visita (sem dados privados), Ajudar (crescimento e limpeza, Ferreiro, limites, XP, missão),
-- Curtir, recados de emojis, bloqueio, denúncia e novidades.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);  -- o clima não interfere na conta do crescimento
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  s jsonb; v jsonb; t double precision; r0 double precision; r1 double precision; v_xp numeric; k int;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8-a-' || a || '@exemplo.test', '{"nickname":"Vizinha8a","birth_date":"1990-01-01"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8-b-' || b || '@exemplo.test', '{"nickname":"Vizinho8b","birth_date":"1990-01-01"}', now(), now()),
    (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f8-c-' || c || '@exemplo.test', '{"nickname":"Terceiro8c","birth_date":"1990-01-01"}', now(), now());

  -- 1. busca pelo começo do apelido (3 letras no mínimo)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.search_players('vizinho8');
  if not exists (select 1 from jsonb_array_elements(s) x where x ->> 'id' = b::text and x ->> 'status' = 'none') then raise exception 'FALHA 1: busca %', s; end if;
  if exists (select 1 from jsonb_array_elements(s) x where x ->> 'id' = a::text) then raise exception 'FALHA 2: busca achou a si mesmo'; end if;
  begin perform public.search_players('vi'); raise exception 'FALHA 3: busca com 2 letras';
  exception when check_violation then null; end;

  -- 2. pedido e aceite
  s := public.friend_request(b);
  begin perform public.friend_request(b); raise exception 'FALHA 4: pedido repetido';
  exception when check_violation then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_social();
  if jsonb_array_length(s -> 'incoming') <> 1 then raise exception 'FALHA 5: pedido não chegou %', s; end if;
  s := public.friend_respond(a, true);
  if jsonb_array_length(s -> 'friends') <> 1 then raise exception 'FALHA 6: amizade não feita'; end if;
  reset role;
  -- os dois pedem: vira amizade na hora
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.friend_request(a);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.friend_request(c);
  reset role;
  if public.friend_status(a, c) <> 'friend' then raise exception 'FALHA 7: pedido cruzado não virou amizade'; end if;

  -- 3. visita: a fazenda aparece, mas sem ouro, Silo, inventário, cartas ou missões
  update public.plots set crop_id = 'alface' where user_id = b and plot_id like 'A1-%';
  select farm_time into t from public.farms where user_id = b;
  update public.plots set state = 'growing', planted_crop_id = 'alface', planted_kind = 'crop', planted_at = t, ready_at = t + 36000 where user_id = b and plot_id like 'A1-%';
  set local role authenticated;
  v := public.visit_farm(b);
  reset role;
  if v -> 'state' ? 'gold' or v -> 'state' ? 'silo' or v -> 'state' ? 'inventory' or v -> 'state' ? 'cards' or v -> 'state' ? 'missions' then
    raise exception 'FALHA 8: visita mostra dado privado %', (select jsonb_agg(k) from jsonb_object_keys(v -> 'state') k); end if;
  if jsonb_array_length(v -> 'state' -> 'plots') < 1 or v -> 'owner' ->> 'status' <> 'friend' then raise exception 'FALHA 9: visita sem a fazenda'; end if;
  set local role authenticated;
  begin perform public.visit_farm(a); raise exception 'FALHA 10: visitou a si mesmo';
  exception when check_violation then null; end;
  reset role;

  -- 4. Ajudar no crescimento: +10% por 1 h, XP para quem ajuda, missão de ajudar
  select xp into v_xp from public.farms where user_id = a;
  set local role authenticated;
  v := public.help_lot(b, 'A1');
  begin perform public.help_lot(b, 'A1'); raise exception 'FALHA 11: mesmo lote ajudado de novo';
  exception when check_violation then null; end;
  reset role;
  if not exists (select 1 from public.lot_helps where owner = b and helper = a and lot_id = 'A1' and kind = 'growth' and pct = 10) then raise exception 'FALHA 12: ajuda não gravada'; end if;
  if (select xp from public.farms where user_id = a) <= v_xp and (select level from public.farms where user_id = a) = 1 then raise exception 'FALHA 13: quem ajudou não ganhou XP'; end if;
  if exists (select 1 from public.missions where user_id = a and metric = 'neighbors_helped')
     and not exists (select 1 from public.missions where user_id = a and metric = 'neighbors_helped' and progress >= 1) then raise exception 'FALHA 14: missão de ajudar não andou'; end if;
  if jsonb_array_length(public.social_badge(b) -> 'social' -> 'helps') <> 1 then raise exception 'FALHA 15: dono não vê a ajuda'; end if;

  -- 5. o lote ajudado cresce 10% mais rápido (30 min passados → 3 min a mais); os outros lotes não
  update public.lot_helps set started_at = now() - interval '1 hour', ends_at = now() + interval '1 hour' where owner = b;
  insert into public.owned_lots (user_id, lot_id, ready_at) values (b, 'A3', 0) on conflict do nothing;
  insert into public.plots (user_id, plot_id, crop_id, state, planted_crop_id, planted_kind, planted_at, ready_at)
    values (b, 'A3-1', 'alface', 'growing', 'alface', 'crop', t, t + 36000) on conflict (user_id, plot_id) do update set state = 'growing', planted_crop_id = 'alface', ready_at = t + 36000;
  update public.plots set ready_at = t + 36000 where user_id = b and plot_id = 'A1-1';
  update public.farms set farm_time = t, synced_at = now() - interval '30 minutes', last_activity_at = now() where user_id = b;
  perform public.advance_farm(b, now());
  r0 := (select ready_at from public.plots where user_id = b and plot_id = 'A1-1') - (t + 36000);
  r1 := (select ready_at from public.plots where user_id = b and plot_id = 'A3-1') - (t + 36000);
  if abs(r0 + 180) > 2 then raise exception 'FALHA 16: lote ajudado adiantou % s (esperado 180)', -r0; end if;
  if abs(r1) > 0.5 then raise exception 'FALHA 17: lote sem ajuda mudou % s', r1; end if;

  -- 6. Ajudar na limpeza: −10% do que falta; com o Ferreiro (Obras B 5) do dono, −15%
  insert into public.characters (user_id, class_id, skills) values (b, 'ferreiro', '{"obras.b": 5}');
  insert into public.owned_lots (user_id, lot_id, ready_at) values (b, 'A4', 0) on conflict do nothing;
  select farm_time into t from public.farms where user_id = b;
  update public.owned_lots set ready_at = t + 1000 where user_id = b and lot_id = 'A4';
  set local role authenticated;
  v := public.help_lot(b, 'A4');
  reset role;
  select farm_time into t from public.farms where user_id = b;
  if (select pct from public.lot_helps where owner = b and lot_id = 'A4') <> 15 then raise exception 'FALHA 18: Ferreiro não aumentou (%)', (select pct from public.lot_helps where owner = b and lot_id = 'A4'); end if;
  if abs((select ready_at from public.owned_lots where user_id = b and lot_id = 'A4') - t - 850) > 3 then
    raise exception 'FALHA 19: limpeza ficou em % s (esperado 850)', (select ready_at from public.owned_lots where user_id = b and lot_id = 'A4') - t; end if;
  -- lote sem nada para ajudar
  update public.plots set state = 'empty', planted_crop_id = null, ready_at = null where user_id = b and plot_id like 'A3-%';
  set local role authenticated;
  begin perform public.help_lot(b, 'A3'); raise exception 'FALHA 20: ajudou lote vazio';
  exception when check_violation then null; end;
  reset role;

  -- 7. limites: 10 ajudas dadas por dia (e 10 recebidas)
  insert into public.lot_helps (owner, helper, lot_id, kind, pct, started_at, ends_at, given_day, received_day)
    select c, a, 'Z' || g, 'growth', 10, now() - interval '3 hours', now() - interval '2 hours', public.user_day(a, now()), public.user_day(c, now()) from generate_series(1, 8) g;
  update public.plots set state = 'growing', planted_crop_id = 'alface', ready_at = t + 36000 where user_id = c and plot_id like 'A1-%';
  set local role authenticated;
  begin perform public.help_lot(c, 'A1'); raise exception 'FALHA 21: 11ª ajuda do dia aceita';
  exception when check_violation then null; end;
  reset role;

  -- 8. Curtir: 1 por dia por fazenda
  set local role authenticated;
  v := public.like_farm(b);
  begin perform public.like_farm(b); raise exception 'FALHA 22: curtiu 2 vezes';
  exception when check_violation then null; end;
  reset role;
  if (select likes_total from public.farms where user_id = b) <> 1 then raise exception 'FALHA 23: curtida não contou'; end if;

  -- 9. recado: só emojis da lista, 1 por dia por fazenda
  set local role authenticated;
  begin perform public.send_note(b, array['oi']); raise exception 'FALHA 24: texto livre aceito';
  exception when check_violation then null; end;
  begin perform public.send_note(b, array['👍', '👍', '👍', '👍']); raise exception 'FALHA 25: 4 emojis aceitos';
  exception when check_violation then null; end;
  v := public.send_note(b, array['🌻', '👍']);
  begin perform public.send_note(b, array['⭐']); raise exception 'FALHA 26: 2º recado no dia';
  exception when check_violation then null; end;
  reset role;

  -- 10. novidades do dono: ajuda, curtida e recado; depois de ver, zera
  s := public.social_state(b);
  if not exists (select 1 from jsonb_array_elements(s -> 'activity') x where x ->> 'kind' = 'note' and x -> 'emojis' ? '🌻')
     or not exists (select 1 from jsonb_array_elements(s -> 'activity') x where x ->> 'kind' = 'like')
     or not exists (select 1 from jsonb_array_elements(s -> 'activity') x where x ->> 'kind' = 'help') then raise exception 'FALHA 27: novidades %', s -> 'activity'; end if;
  update public.farms set social_seen_at = now() - interval '1 day' where user_id = b;
  if (public.social_badge(b) -> 'social' ->> 'unseen')::int < 3 then raise exception 'FALHA 28: contador de novidades'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.social_seen();
  reset role;
  if (public.social_badge(b) -> 'social' ->> 'unseen')::int <> 0 then raise exception 'FALHA 29: novidades não zeraram'; end if;

  -- 11. bloqueio: desfaz a amizade; o bloqueado não acha, não visita e não ajuda
  set local role authenticated;
  s := public.block_player(a, true);
  reset role;
  if public.friend_status(a, b) = 'friend' then raise exception 'FALHA 30: bloqueio não desfez a amizade'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if exists (select 1 from jsonb_array_elements(public.search_players('vizinho8')) x where x ->> 'id' = b::text) then raise exception 'FALHA 31: bloqueado acha quem bloqueou'; end if;
  begin perform public.visit_farm(b); raise exception 'FALHA 32: bloqueado visitou';
  exception when check_violation then null; end;
  begin perform public.like_farm(b); raise exception 'FALHA 33: bloqueado curtiu';
  exception when check_violation then null; end;

  -- 12. denúncia: motivo da lista, 1 por dia por jogador, registrada
  s := public.report_player(c, 'apelido');
  begin perform public.report_player(c, 'apelido'); raise exception 'FALHA 34: denúncia repetida';
  exception when check_violation then null; end;
  begin perform public.report_player(b, 'xingou'); raise exception 'FALHA 35: motivo fora da lista';
  exception when check_violation then null; end;
  reset role;
  if not exists (select 1 from public.player_reports where reporter = a and target = c and reason = 'apelido')
     or not exists (select 1 from public.audit_log where action = 'social.report' and actor_id = a) then raise exception 'FALHA 36: denúncia não registrada'; end if;

  -- 13. visita aleatória: só fazendas ativas de outros jogadores, nunca quem bloqueou
  update public.farms set level = 5, last_activity_at = now() where user_id in (b, c);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  for k in 1 .. 10 loop
    v := public.visit_farm(null);
    if v -> 'owner' ->> 'id' in (a::text, b::text) then raise exception 'FALHA 37: visita aleatória caiu em %', v -> 'owner' ->> 'nickname'; end if;
  end loop;
  reset role;

  raise exception 'TESTES_OK';
end $$;
