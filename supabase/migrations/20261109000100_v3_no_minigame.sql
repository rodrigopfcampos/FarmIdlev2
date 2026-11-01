-- Reformulação v3 (pedido do dono em 01/11): fim do minigame de setas. A expedição parte direto (sem minigame) e conta
-- como "Concluída" (0 pontos). O minigame antigo continua aceito para não quebrar quem estiver com a tela aberta.

create or replace function public.launch_expedition(p_minigame uuid, p_keys jsonb, p_vehicles text[], p_route text, p_cargo jsonb,
  p_insurance boolean, p_manager boolean, p_repeat boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); e jsonb := public.config_get('expeditions'); r jsonb := public.exp_route(p_route);
  mg public.minigames; ev jsonb; v public.vehicles; lead jsonb; fx jsonb; v_time double precision; v_level int; v_convoy uuid := gen_random_uuid();
  v_vid text; v_n int := 0; v_led int := 0; v_cap int; v_part jsonb; v_rest jsonb; c record; v_take int; v_total int; v_gold numeric; v_ins numeric;
  v_idx int; v_used int; v_value numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if r is null then raise exception 'rota não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if p_minigame is null then
    -- v3: sem minigame (jogo idle): a partida vale como Concluída, sem bônus nem penalidade
    ev := jsonb_build_object('result', 'done', 'robot', false);
  else
    select * into mg from public.minigames where id = p_minigame and user_id = v_user for update;
    if not found or mg.used then raise exception 'minigame inválido' using errcode = 'check_violation'; end if;
    if mg.route_id <> p_route or mg.vehicles <> coalesce(array_length(p_vehicles, 1), 0) or mg.manager <> coalesce(p_manager, false) then
      raise exception 'minigame não confere com a expedição' using errcode = 'check_violation';
    end if;
    update public.minigames set used = true where id = mg.id;
    -- partida velha demais (abandonada) conta como Falhou
    if now() - mg.started_at > make_interval(secs => (e -> 'minigame' ->> 'start_valid_s')::double precision + mg.limit_ms / 1000.0) then
      ev := jsonb_build_object('result', 'failed', 'robot', false);
    else
      ev := public.minigame_eval(mg, p_keys);
    end if;
    if (ev ->> 'robot')::boolean then
      insert into public.audit_log (actor_id, action, target_user_id, data)
        values (v_user, 'cheat.minigame_robot', v_user, jsonb_build_object('minigame', mg.id, 'keys', p_keys, 'eval', ev));
    end if;
  end if;

  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if (r ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente para a rota' using errcode = 'check_violation'; end if;
  if p_insurance and r ->> 'insurance_pct' is null then raise exception 'essa rota não tem seguro' using errcode = 'check_violation'; end if;
  if p_cargo is null or p_cargo = '{}'::jsonb then raise exception 'escolha a carga' using errcode = 'check_violation'; end if;
  if coalesce(p_manager, false) then
    lead := public.lead_info(v_user);
    if lead is null or not (lead ->> 'available')::boolean then raise exception 'o Gerente não pode conduzir agora' using errcode = 'check_violation'; end if;
  end if;
  fx := public.team_fx(v_user);
  perform public.exp_take_cargo(v_user, p_cargo);
  v_rest := p_cargo;

  foreach v_vid in array p_vehicles loop
    v_n := v_n + 1;
    select * into v from public.vehicles where user_id = v_user and vehicle_id = v_vid for update;
    if not found then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
    if v.refurb_until is not null then raise exception 'veículo na reforma' using errcode = 'check_violation'; end if;
    if v.from_card is not null and not exists (select 1 from public.card_buffs where user_id = v_user and serial = v.from_card) then
      raise exception 'a carta desse veículo saiu da mão' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = v_vid and status in ('travel', 'back')) then
      raise exception 'veículo ocupado (viajando ou esperando Receber)' using errcode = 'check_violation';
    end if;
    if public.exp_route_idx(p_route) > public.exp_route_idx(public.vehicle_def(v_vid) ->> 'max_route') then
      raise exception 'esse veículo não vai até essa rota' using errcode = 'check_violation';
    end if;
    -- a carga enche os veículos na ordem escolhida
    v_cap := floor(public.exp_capacity(v, case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then lead end)
                   * (1 + public.jnum(fx -> 'exp_card', 'cargo') / 100))::int;  -- carta de Veículo
    v_part := '{}'; v_used := 0;
    for c in select key, value::int q from jsonb_each_text(v_rest) where value::int > 0 order by key loop
      v_take := least(c.q, v_cap - v_used);
      exit when v_take <= 0;
      v_part := v_part || jsonb_build_object(c.key, v_take);
      v_rest := v_rest || jsonb_build_object(c.key, c.q - v_take);
      v_used := v_used + v_take;
    end loop;
    if v_used = 0 then raise exception 'carga vazia para um dos veículos' using errcode = 'check_violation'; end if;
    select gold into v_gold from public.wallets where user_id = v_user;
    if coalesce(p_insurance, false) then
      v_value := public.exp_cargo_value(v_part, p_route, public.game_day(now()));
      v_ins := round(v_value * (r ->> 'insurance_pct')::numeric / 100
               * (1 + case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then (lead ->> 'insurance_pct')::numeric else 0 end / 100), 2);
      if v_ins > v_gold then raise exception 'ouro insuficiente para o seguro' using errcode = 'check_violation'; end if;
    end if;
    perform public.exp_depart(v_user, v_convoy, v, p_route, v_part,
      coalesce(p_insurance, false), case when coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then lead end,
      ev ->> 'result', v_time, 0, case when coalesce(p_repeat, false) then (e ->> 'auto_repeat_max')::int else 0 end, fx, v_gold);
    if coalesce(p_manager, false) and v_led < (lead ->> 'vehicles')::int then v_led := v_led + 1; end if;
  end loop;
  select coalesce(sum(value::int), 0) into v_total from jsonb_each_text(v_rest);
  if v_total > 0 then raise exception 'carga maior que a capacidade' using errcode = 'check_violation'; end if;
  if v_led > 0 then update public.characters set leading_id = v_convoy where user_id = v_user and class_id = 'gerente'; end if;
  update public.vehicles set active = (vehicle_id = p_vehicles[1]) where user_id = v_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'expedition.launched', v_user, jsonb_build_object('convoy', v_convoy, 'route', p_route, 'vehicles', p_vehicles,
      'cargo', p_cargo, 'insurance', p_insurance, 'manager', p_manager, 'minigame', ev));
  return public.farm_state(v_user) || jsonb_build_object('minigame', ev);
end;
$$;
