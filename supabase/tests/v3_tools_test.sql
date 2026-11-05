-- Testes do ajuste das ferramentas (v3): ferramenta sobe sozinha com o nível, Vara de Pescar é do Pescador,
-- limpeza 3× mais rápida com o Ferreiro em campo. Esperado: erro "TESTES_OK" (tudo é desfeito).
select set_config('vif.weather', 'off', false);
select set_config('vif.missions', 'off', false);
do $$
declare a uuid := gen_random_uuid(); s jsonb; t double precision; v_gold numeric; q int; c jsonb := public.config_get('lots') -> 'rules' -> 'cleanup';
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tools-' || a || '@exemplo.test', '{"nickname":"Tools","birth_date":"1990-01-01"}', now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.advance_farm(a);

  -- 1. ferramenta sobe sozinha com o nível (Cobre no 8, Ferro no 18) e a Forja não vende mais
  if (select material from public.tools where user_id = a and class_id = 'agricultor') <> 'wood' then raise exception 'FALHA 1: começa em madeira'; end if;
  update public.farms set level = 18 where user_id = a;
  perform public.advance_farm(a);
  if (select material from public.tools where user_id = a and class_id = 'agricultor') <> 'iron' then raise exception 'FALHA 2: não subiu com o nível (%)', (select material from public.tools where user_id = a and class_id = 'agricultor'); end if;
  update public.farms set level = 10 where user_id = a;
  perform public.advance_farm(a);
  if (select material from public.tools where user_id = a and class_id = 'agricultor') <> 'iron' then raise exception 'FALHA 3: desceu'; end if;
  set local role authenticated;
  begin perform public.upgrade_tool('agricultor'); raise exception 'FALHA 4: Forja ainda vende';
  exception when undefined_function then null; end; -- v3: a função foi removida
  reset role;

  -- 2. (04/11) a Vara de Pescar é a ferramenta do Pescador: a rede e a vara da fazenda saíram
  set local role authenticated;
  begin perform public.repair_rod(); raise exception 'FALHA 5: vara da fazenda ainda existe';
  exception when undefined_function then null; end;
  begin perform public.collect_fish(); raise exception 'FALHA 6: rede de pesca ainda existe';
  exception when undefined_function then null; end;
  reset role;
  if not exists (select 1 from jsonb_array_elements(public.config_get('tools_and_items') -> 'class_tool_cards') x where x ->> 'class_id' = 'pescador' and x ->> 'id' = 'tool_rod') then
    raise exception 'FALHA 7: Vara de Pescar não é do Pescador'; end if;

  -- 3. limpeza: sem Ferreiro 60 + 12 n; com ele em campo, 3× mais rápida
  if (c ->> 'base_minutes')::numeric * (c ->> 'other_class_multiplier')::numeric <> 60
     or (c ->> 'per_purchase_minutes')::numeric * (c ->> 'other_class_multiplier')::numeric <> 12 then raise exception 'FALHA 10: limpeza %', c; end if;

  raise exception 'TESTES_OK';
end $$;
