-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.process_expeditions(p_user uuid, p_t double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; v public.vehicles; fx jsonb; lead jsonb; v_cargo jsonb; v_cap int; v_left int; c record; v_take int;
  v_gold numeric; i int := 0;
begin
  perform public.demand_ensure(public.game_day(now()));
  perform public.demand_ensure(public.game_day(now()) + 1);
  update public.vehicles set rarity = refurb_rarity, refurb_rarity = null, refurb_until = null
    where user_id = p_user and refurb_until is not null and refurb_until <= p_t;
  if not exists (select 1 from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t) then return; end if;
  loop
    i := i + 1; exit when i > 200;
    select * into x from public.expeditions where user_id = p_user and status = 'travel' and returns_at <= p_t order by returns_at, id limit 1;
    exit when not found;
    -- o clima, a noite e a Lua Cheia valem pela hora real em que o veículo volta
    perform set_config('vif.at', (select (fa.synced_at + make_interval(secs => x.returns_at - fa.farm_time))::text from public.farms fa where fa.user_id = p_user), true);
    fx := public.team_fx(p_user);
    perform public.exp_resolve(x.id, fx);
    if x.repeat_left > 0 then
      -- repetição: mesmos produtos da viagem, até a capacidade, com o que houver no Silo
      select * into v from public.vehicles where user_id = p_user and vehicle_id = x.vehicle_id;
      lead := case when x.led then public.lead_info(p_user) else null end;
      v_cap := floor(public.exp_capacity(v, lead) * (1 + public.jnum(fx -> 'exp_card', 'cargo') / 100))::int; v_left := v_cap; v_cargo := '{}';
      -- veículo da carta: sem a carta na mão, não repete
      if v.vehicle_id is null or (v.from_card is not null and not exists (select 1 from public.card_buffs where user_id = p_user and serial = v.from_card)) then v_left := 0; end if;
      for c in select key, value::int q from jsonb_each_text(x.cargo) order by value::int desc, key loop
        select least(coalesce(max(qty), 0), v_left) into v_take from public.silo where user_id = p_user and item_id = c.key;
        if v_take > 0 then v_cargo := v_cargo || jsonb_build_object(c.key, v_take); v_left := v_left - v_take; end if;
      end loop;
      if v_cargo <> '{}'::jsonb then
        perform public.exp_take_cargo(p_user, v_cargo);
        select gold into v_gold from public.wallets where user_id = p_user;
        perform public.exp_depart(p_user, x.convoy_id, v, x.route_id, v_cargo, x.insurance > 0, lead, x.minigame, x.returns_at,
          x.seq + 1, x.repeat_left - 1, fx, v_gold);
      end if;
    end if;
    -- o Gerente volta quando nenhum veículo que ele conduz está viajando
    if x.led and not exists (select 1 from public.expeditions where user_id = p_user and convoy_id = x.convoy_id and led and status = 'travel') then
      update public.characters set leading_id = null where user_id = p_user and class_id = 'gerente' and leading_id = x.convoy_id;
    end if;
  end loop;
  perform set_config('vif.at', '', true);
end;
$function$;
