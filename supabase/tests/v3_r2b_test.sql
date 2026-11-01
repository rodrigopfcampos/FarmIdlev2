-- Testes do ajuste da R2: de onde vêm as cartas (presente inicial, cartas por nível, pacote das diárias).
-- Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'on', false);
do $$
declare
  a uuid := gen_random_uuid(); n int; m record; w date;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r2b-' || a || '@exemplo.test', '{"nickname":"R2b","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.advance_farm(a);

  -- 1. presente inicial: Sol, Cesta e Coruja Comuns já na mão, soltas, e só uma vez
  if (select count(*) from public.card_buffs where user_id = a) <> 3 then raise exception 'FALHA 1: mão inicial %', (select count(*) from public.card_buffs where user_id = a); end if;
  if exists (select 1 from public.card_buffs where user_id = a and (rarity <> 'common' or locked_until > now())) then raise exception 'FALHA 2: presente fora da regra'; end if;
  if (select count(*) from public.cards where user_id = a and origin = 'starter' and state = 'equipped') <> 3 then raise exception 'FALHA 3: cartas do presente'; end if;
  perform public.advance_farm(a);
  if (select count(*) from public.cards where user_id = a and origin = 'starter') <> 3 then raise exception 'FALHA 4: presente repetido'; end if;

  -- 2. 1 carta por nível do 2 ao 10, uma vez só
  perform public.add_xp(a, (select sum((x ->> 'xp_to_next')::numeric) from jsonb_array_elements(public.config_get('levels') -> 'levels') with ordinality t(x, i) where i < 5));
  if (select level from public.farms where user_id = a) <> 5 then raise exception 'FALHA 5: nível %', (select level from public.farms where user_id = a); end if;
  if (select count(*) from public.cards where user_id = a and origin = 'level_up') <> 4 then raise exception 'FALHA 6: cartas até o nível 5 = %', (select count(*) from public.cards where user_id = a and origin = 'level_up'); end if;
  perform public.add_xp(a, (select sum((x ->> 'xp_to_next')::numeric) from jsonb_array_elements(public.config_get('levels') -> 'levels') with ordinality t(x, i) where i between 5 and 11));
  if (select level from public.farms where user_id = a) <> 12 then raise exception 'FALHA 7: nível %', (select level from public.farms where user_id = a); end if;
  if (select count(*) from public.cards where user_id = a and origin = 'level_up') <> 9 then raise exception 'FALHA 8: cartas dos níveis 2–10 = %', (select count(*) from public.cards where user_id = a and origin = 'level_up'); end if;

  -- 3. pacote das diárias: 1 carta até o 14, 2 do 15 em diante; sem limite de 4 por semana
  if public.daily_pack_cards(a) <> 1 then raise exception 'FALHA 9: pacote no nível 12'; end if;
  update public.farms set level = 15 where user_id = a;
  if public.daily_pack_cards(a) <> 2 then raise exception 'FALHA 10: pacote no nível 15'; end if;
  w := public.mission_week(public.user_day(a, now()));
  perform public.mission_ensure(a, now());
  update public.mission_weeks set daily_packs = 4 where user_id = a and week = w;
  for m in select metric, max(target) t from public.missions where user_id = a and kind = 'daily' and done_at is null group by metric loop
    perform public.mission_progress(a, m.metric, m.t);
  end loop;
  select count(*) into n from public.cards where user_id = a and origin = 'daily_pack';
  if n <> 2 then raise exception 'FALHA 11: 5º pacote da semana com % cartas', n; end if;

  -- 4. antitrapaça não conta o presente nem as cartas dos níveis
  if public.config_get('anticheat') -> 'rules' -> 'cards' -> 'ignore_origins' ? 'level_up' is not true then raise exception 'FALHA 12: antitrapaça'; end if;

  raise exception 'TESTES_OK';
end $$;
