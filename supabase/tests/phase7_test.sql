-- Testes da fase 7: missões (sorteio, progresso, prêmios, pacote, semanais, troca grátis), sorteio das cartas com garantia,
-- buffs (3 no máximo, raridade, efeitos, Moeda da Sorte), Armory, Colecionador, fichário e caixa de entrada, painel.
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);  -- o clima não interfere nas contas dos buffs
do $$
declare
  a uuid := gen_random_uuid();
  adm uuid := gen_random_uuid();
  s jsonb; fx jsonb; n int; k int; v_gold numeric; v_xp numeric; v_serial bigint; v_s2 bigint; r text; m record; c public.cards;
  cnt jsonb := '{}'; v_level int;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f7-a-' || a || '@exemplo.test', '{"nickname":"Fase7 A","birth_date":"1990-01-01"}', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f7-adm-' || adm || '@exemplo.test', '{"nickname":"Fase7 Adm","birth_date":"1990-01-01"}', now(), now());
  update public.profiles set is_admin = true where id = adm;
  perform public.ledger_post(a, 1000000, 'test_grant');

  -- 1. a conta nova recebe 5 diárias e 5 semanais, só de sistemas liberados (sem animais nem 3 personagens)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  reset role;
  if (select count(*) from jsonb_array_elements(s -> 'missions') x where x ->> 'kind' = 'daily') <> 5 then raise exception 'FALHA 1: diárias %', s -> 'missions'; end if;
  if (select count(*) from jsonb_array_elements(s -> 'missions') x where x ->> 'kind' = 'weekly') <> 5 then raise exception 'FALHA 2: semanais'; end if;
  if exists (select 1 from public.missions where user_id = a and mission_id in ('d_animais', 'd_equipe', 'w_animais', 'w_longe')) then raise exception 'FALHA 3: missão de sistema trancado'; end if;
  if exists (select 1 from public.missions where user_id = a and kind = 'daily' and ((reward ->> 'gold')::numeric <= 0 or (reward ->> 'xp')::numeric <= 0)) then raise exception 'FALHA 4: diária sem prêmio'; end if;

  -- 2. vender na Barraca avança "vender" e "ganhar ouro"
  insert into public.silo (user_id, item_id, qty) values (a, 'batata', 10);
  set local role authenticated;
  s := public.sell_at_stall('batata', 10, 'f7-venda-' || a);
  reset role;
  if not exists (select 1 from public.missions where user_id = a and metric in ('stall_gold', 'gold_earned') and progress > 0)
     and exists (select 1 from public.missions where user_id = a and metric in ('stall_gold', 'gold_earned')) then raise exception 'FALHA 5: venda não contou'; end if;

  -- 3. completar uma diária paga o ouro e o XP fixados; as 5 do dia dão 1 pacote (carta nova, ainda não vista)
  -- (com o Comerciante em campo e Negócios B cheio: +25% no ouro da missão)
  insert into public.characters (user_id, class_id, skills) values (a, 'comerciante', '{"negocios.b": 5}');
  select gold into v_gold from public.wallets where user_id = a;
  select * into m from public.missions where user_id = a and kind = 'daily' and done_at is null order by slot limit 1;
  perform public.mission_progress(a, m.metric, m.target);
  if abs((select gold from public.wallets where user_id = a) - v_gold - round((m.reward ->> 'gold')::numeric * 1.25, 2)) > 0.02 then
    raise exception 'FALHA 6: diária pagou % (prêmio % com +25%% do Negócios)', (select gold from public.wallets where user_id = a) - v_gold, m.reward ->> 'gold'; end if;
  delete from public.characters where user_id = a and class_id = 'comerciante';
  for m in select metric, max(target) t from public.missions where user_id = a and kind = 'daily' and done_at is null group by metric loop
    perform public.mission_progress(a, m.metric, m.t);
  end loop;
  select count(*) into n from public.cards where user_id = a and origin = 'daily_pack';
  if n <> 1 then raise exception 'FALHA 7: % pacotes das diárias (esperado 1)', n; end if;
  if exists (select 1 from public.cards where user_id = a and seen) then raise exception 'FALHA 8: carta nova já vista'; end if;
  if (select daily_packs from public.mission_weeks where user_id = a) <> 1 then raise exception 'FALHA 9: contador de pacotes'; end if;

  -- 4. semanais: 3 completas = 1 carta; 5 = +1 carta e 1 Escritura
  k := 0;
  for m in select metric, max(target) t from public.missions where user_id = a and kind = 'weekly' and done_at is null group by metric order by metric loop
    perform public.mission_progress(a, m.metric, m.t);
  end loop;
  if (select count(*) from public.cards where user_id = a and origin in ('weekly_3', 'weekly_5')) <> 2 then raise exception 'FALHA 10: cartas das semanais'; end if;
  if coalesce((select qty from public.inventory where user_id = a and item_id = 'deed'), 0) < 1 then raise exception 'FALHA 11: sem Escritura das 5 semanais'; end if;

  -- 5. garantia: 9 cartas sem Raro → a 10ª é Raro ou melhor; 119 sem Mítico → a 120ª é Mítica
  update public.farms set pity_rare = 9 where user_id = a;
  v_serial := public.draw_card(a, 'admin');
  if public.rarity_rank((select rarity from public.cards where serial = v_serial)) < 3 then raise exception 'FALHA 12: garantia do Raro'; end if;
  update public.farms set pity_mythic = 119 where user_id = a;
  v_serial := public.draw_card(a, 'admin');
  if (select rarity from public.cards where serial = v_serial) <> 'mythic' then raise exception 'FALHA 13: garantia do Mítico'; end if;
  if (select pity_mythic from public.farms where user_id = a) <> 0 then raise exception 'FALHA 14: contador do Mítico não zerou'; end if;
  -- chances da tabela (3.000 sorteios com o fichário grande o bastante)
  update public.farms set binder_slots = 5000 where user_id = a;
  for k in 1 .. 3000 loop
    v_serial := public.draw_card(a, 'admin');
  end loop;
  select count(*) filter (where rarity = 'common'), count(*) filter (where rarity = 'mythic') into n, k from (select rarity from public.cards where user_id = a order by serial desc limit 3000) x;
  if n < 1300 or n > 1600 then raise exception 'FALHA 15: % Comuns em 3.000 (esperado ~1.450)', n; end if;
  if k < 20 or k > 80 then raise exception 'FALHA 16: % Míticas em 3.000 (esperado ~45)', k; end if;
  delete from public.cards where user_id = a and origin = 'admin';
  update public.farms set binder_slots = 60 where user_id = a;

  -- 6. usar carta: buff ativo com o efeito; raridade menor recusada; no máximo 3 buffs
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'sol_de_verao', 'mythic', 'admin') returning serial into v_serial;
  set local role authenticated;
  s := public.use_card(v_serial);
  reset role;
  if jsonb_array_length(s -> 'buffs') <> 1 then raise exception 'FALHA 17: buff não ligou'; end if;
  fx := public.team_fx(a);
  if abs((fx ->> 'w_growth')::numeric - 0.60) > 0.001 then raise exception 'FALHA 18: Sol de Verão Mítico deu % de crescimento', fx ->> 'w_growth'; end if;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'sol_de_verao', 'rare', 'admin') returning serial into v_serial;
  set local role authenticated;
  begin perform public.use_card(v_serial); raise exception 'FALHA 19: raridade menor trocou o buff';
  exception when check_violation then null; end;
  reset role;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'coruja_sabia', 'common', 'admin'), (a, 'folego', 'mythic', 'admin'), (a, 'moeda_da_sorte', 'common', 'admin');
  set local role authenticated;
  perform public.use_card((select serial from public.cards where user_id = a and card_id = 'coruja_sabia' and rarity = 'common' and state = 'binder' limit 1));
  perform public.use_card((select serial from public.cards where user_id = a and card_id = 'folego' and rarity = 'mythic' and state = 'binder' limit 1));
  begin perform public.use_card((select serial from public.cards where user_id = a and card_id = 'moeda_da_sorte' and rarity = 'common' and state = 'binder' limit 1));
    raise exception 'FALHA 20: 4º buff aceito';
  exception when check_violation then null; end;
  reset role;
  fx := public.team_fx(a);
  if abs((fx ->> 'account_xp')::numeric - 0.15) > 0.001 then raise exception 'FALHA 21: Coruja Comum deu % de XP', fx ->> 'account_xp'; end if;
  if (public.char_energy((select ch from public.characters ch where user_id = a and class_id = 'agricultor'), fx) ->> 'use')::numeric <> 0 then raise exception 'FALHA 22: Fôlego Mítico ainda gasta energia'; end if;

  -- 7. Moeda da Sorte: % do valor produzido no buff, pago no fim
  delete from public.card_buffs where user_id = a and card_id in ('coruja_sabia', 'folego');
  set local role authenticated;
  perform public.use_card((select serial from public.cards where user_id = a and card_id = 'moeda_da_sorte' and rarity = 'common' and state = 'binder' limit 1));
  reset role;
  update public.card_buffs set coin_value = 0 where user_id = a;  -- só conta a produção abaixo
  perform public.produced(a, 'batata', 100, 0, 'crop');
  if abs((select coin_value from public.card_buffs where user_id = a and card_id = 'moeda_da_sorte') - round(100 * public.item_price('batata') * 0.13, 2)) > 0.02 then
    raise exception 'FALHA 23: Moeda juntou %', (select coin_value from public.card_buffs where user_id = a and card_id = 'moeda_da_sorte'); end if;
  select gold into v_gold from public.wallets where user_id = a;
  update public.card_buffs set ends_at = now() - interval '1 second', started_at = now() - interval '2 hours' where user_id = a and card_id = 'moeda_da_sorte';
  perform public.buffs_expire(a, now());
  if (select gold from public.wallets where user_id = a) <= v_gold then raise exception 'FALHA 24: Moeda não pagou no fim'; end if;

  -- 8. Estrada Livre: fica gravada na expedição que parte no buff
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'estrada_livre', 'mythic', 'admin') returning serial into v_serial;
  set local role authenticated;
  perform public.use_card(v_serial);
  reset role;
  fx := public.team_fx(a);
  if (fx -> 'exp_card' ->> 'loss_red')::numeric <> 100 or (fx -> 'exp_card' ->> 'crit_pts')::numeric <> 36 then raise exception 'FALHA 25: Estrada Livre %', fx -> 'exp_card'; end if;

  -- 9. Armory: Comum + Incomum + Raro = bônus parcial; a mesma raridade de novo é recusada
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'rebanho_feliz', 'common', 'admin'), (a, 'rebanho_feliz', 'uncommon', 'admin'),
    (a, 'rebanho_feliz', 'rare', 'admin'), (a, 'rebanho_feliz', 'rare', 'admin');
  set local role authenticated;
  for v_serial in select serial from public.cards where user_id = a and card_id = 'rebanho_feliz' and origin = 'admin' and state = 'binder' order by serial limit 3 loop
    perform public.armory_place(v_serial);
  end loop;
  begin perform public.armory_place((select serial from public.cards where user_id = a and card_id = 'rebanho_feliz' and rarity = 'rare' and state = 'binder' limit 1));
    raise exception 'FALHA 26: mesma raridade duas vezes no Armory';
  exception when check_violation then null; end;
  reset role;
  if public.jnum(public.card_fx(a, now()) -> 'armory', 'animal_production_pct') <> 8 then raise exception 'FALHA 27: bônus parcial %', public.card_fx(a, now()); end if;

  -- 10. Colecionador paga a raridade sobre o R do nível
  select level into v_level from public.farms where user_id = a;
  select gold into v_gold from public.wallets where user_id = a;
  set local role authenticated;
  perform public.sell_card((select serial from public.cards where user_id = a and card_id = 'rebanho_feliz' and rarity = 'rare' and state = 'binder' limit 1));
  reset role;
  if abs((select gold from public.wallets where user_id = a) - v_gold - round(public.ref_income(v_level) * 0.008, 2)) > 0.01 then raise exception 'FALHA 28: preço do Colecionador'; end if;

  -- 11. fichário cheio: a carta vai para a caixa de entrada; vencida, o Colecionador compra sozinho
  update public.farms set binder_slots = (select count(*) from public.cards where user_id = a and state = 'binder') where user_id = a;
  v_serial := public.draw_card(a, 'admin');
  if (select state from public.cards where serial = v_serial) <> 'inbox' then raise exception 'FALHA 29: fichário cheio aceitou'; end if;
  update public.cards set inbox_until = now() - interval '1 minute' where serial = v_serial;
  perform public.cards_maintain(a);
  if (select state from public.cards where serial = v_serial) <> 'sold' then raise exception 'FALHA 30: caixa de entrada vencida'; end if;
  -- ampliar: +20 por 50% do R
  select gold into v_gold from public.wallets where user_id = a;
  select binder_slots into n from public.farms where user_id = a;
  set local role authenticated;
  perform public.binder_expand();
  reset role;
  if (select binder_slots from public.farms where user_id = a) <> n + 20 or abs(v_gold - (select gold from public.wallets where user_id = a) - round(public.ref_income(v_level) * 0.5, 2)) > 0.01 then
    raise exception 'FALHA 31: ampliação do fichário'; end if;

  -- 12. troca grátis: 1 por dia, só de missão não completa
  delete from public.missions where user_id = a and kind = 'daily';
  update public.farms set daily_pack_day = null where user_id = a;
  perform public.mission_ensure(a, now());
  set local role authenticated;
  s := public.reroll_mission(1);
  begin perform public.reroll_mission(2); raise exception 'FALHA 32: 2ª troca no mesmo dia';
  exception when check_violation then null; end;
  s := public.cards_seen();
  reset role;
  if exists (select 1 from public.cards where user_id = a and not seen) then raise exception 'FALHA 33: cartas continuam novas'; end if;

  -- 13. painel: só admin dá carta e completa missões; fica registrado
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin perform public.admin_grant_card(a, 'sol_de_verao', 'mythic', 'teste de jogador'); raise exception 'FALHA 34: jogador se deu carta';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  s := public.admin_grant_card(a, 'trevo_quatro_folhas', 'legendary', 'teste do painel');
  s := public.admin_complete_missions(a, 'daily', 'teste do painel');
  reset role;
  if not exists (select 1 from public.cards where user_id = a and card_id = 'trevo_quatro_folhas' and rarity = 'legendary') then raise exception 'FALHA 35: painel não deu carta'; end if;
  if exists (select 1 from public.missions where user_id = a and kind = 'daily' and period = public.user_day(a, now()) and done_at is null) then raise exception 'FALHA 36: painel não completou'; end if;
  if not exists (select 1 from public.audit_log where action = 'admin.complete_missions' and actor_id = adm) then raise exception 'FALHA 37: sem registro'; end if;

  raise exception 'TESTES_OK';
end $$;
