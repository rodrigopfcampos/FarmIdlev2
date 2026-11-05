-- Testes da expedição v3: parte direto, sem minigame (vale como Concluída, 0 pontos). Esperado: erro "TESTES_OK".
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare a uuid := gen_random_uuid(); s jsonb; x public.expeditions; v_p bigint; v_s bigint;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exp3-' || a || '@exemplo.test', '{"nickname":"Exp3","birth_date":"1990-01-01"}', now(), now());
  insert into public.silo (user_id, item_id, qty) values (a, 'batata', 100);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  s := public.get_farm();
  -- cartas por uso: a Prancheta (expedição) gasta 1 uso ao partir; o Sol (lavoura e pomar) não
  reset role;
  delete from public.card_buffs where user_id = a;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'prancheta', 'rare', 'admin') returning serial into v_p;
  insert into public.cards (user_id, card_id, rarity, origin) values (a, 'sol', 'uncommon', 'admin') returning serial into v_s;
  set local role authenticated;
  s := public.equip_card(v_p);
  s := public.equip_card(v_s);
  s := public.launch_expedition(null, '[]', array['carroca'], 'feira', '{"batata":40}', false, false, false);
  reset role;
  select * into x from public.expeditions where user_id = a;
  if not found or x.status <> 'travel' then raise exception 'FALHA 1: não partiu'; end if;
  if x.minigame <> 'done' then raise exception 'FALHA 2: minigame %', x.minigame; end if;
  if (select qty from public.silo where user_id = a and item_id = 'batata') <> 60 then raise exception 'FALHA 3: carga não saiu do Silo'; end if;
  if exists (select 1 from public.audit_log where target_user_id = a and action = 'cheat.minigame_robot') then raise exception 'FALHA 4: robô sem minigame'; end if;
  if (select uses_left from public.card_buffs where user_id = a and card_id = 'prancheta') <> 2
     or (select uses_left from public.card_buffs where user_id = a and card_id = 'sol') <> 2 then
    raise exception 'FALHA 5: usos na partida (prancheta %, sol %)', (select uses_left from public.card_buffs where user_id = a and card_id = 'prancheta'), (select uses_left from public.card_buffs where user_id = a and card_id = 'sol'); end if;
  raise exception 'TESTES_OK';
end $$;
