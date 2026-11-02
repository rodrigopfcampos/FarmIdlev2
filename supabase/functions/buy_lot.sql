-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.buy_lot(p_lot text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_lots jsonb := public.config_get('lots');
  v_map jsonb := public.config_get('map_rules');
  v_lot jsonb := public.lot_def(p_lot);
  v_n int; v_row jsonb; v_need_level int; v_level int; v_cost numeric; v_deed boolean;
  v_time double precision; v_minutes double precision; v_ready double precision;
  v_neighbor boolean; k int; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if v_lot is null then raise exception 'lote não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.owned_lots where user_id = v_user and lot_id = p_lot) then
    raise exception 'esse lote já é seu' using errcode = 'check_violation';
  end if;
  select count(*) into v_n from public.owned_lots where user_id = v_user;
  v_row := v_lots -> 'purchases' -> (v_n - 1);
  if v_row is null then raise exception 'todos os lotes já foram comprados' using errcode = 'check_violation'; end if;
  v_neighbor := (v_map -> 'exempt_types') ? (v_lot ->> 'type')
    or exists (select 1 from jsonb_array_elements_text(v_lot -> 'neighbors') nb
               join public.owned_lots ol on ol.user_id = v_user and ol.lot_id = nb);
  if not v_neighbor then raise exception 'lote não é vizinho' using errcode = 'check_violation'; end if;
  select level, farm_time into v_level, v_time from public.farms where user_id = v_user;
  v_need_level := greatest((v_row ->> 'min_level')::int, coalesce((v_lots -> 'rules' -> 'min_level' -> 'type_floor' ->> (v_lot ->> 'type'))::int, 0));
  if v_level < v_need_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_deed := (v_row ->> 'requires_deed')::boolean;
  if v_deed then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'deed' and qty >= 1;
    if not found then raise exception 'precisa de Escritura' using errcode = 'check_violation'; end if;
  end if;
  v_cost := (v_row ->> 'cost')::numeric;
  perform public.ledger_post(v_user, -v_cost, 'lot_purchase', jsonb_build_object('lot', p_lot, 'n', v_n, 'deed', v_deed), 'lot:' || p_lot);
  fx := public.team_fx(v_user);
  v_minutes := ((v_lots -> 'rules' -> 'cleanup' ->> 'base_minutes')::double precision
               + (v_lots -> 'rules' -> 'cleanup' ->> 'per_purchase_minutes')::double precision * v_n)
               * case when exists (select 1 from public.characters where user_id = v_user and class_id = 'ferreiro') then 1
                      else (v_lots -> 'rules' -> 'cleanup' ->> 'other_class_multiplier')::double precision end
               * (1 + (fx ->> 'cleanup')::double precision);
  v_ready := v_time + v_minutes * 60;
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (v_user, p_lot, v_ready, v_n);
  for k in 1 .. jsonb_array_length(coalesce(v_lot -> 'plots', '[]')) loop
    insert into public.plots (user_id, plot_id, free_since) values (v_user, v_lot -> 'plots' ->> (k - 1), v_ready);
  end loop;
  for k in 1 .. coalesce((v_lot ->> 'tree_slots')::int, 0) loop
    insert into public.trees (user_id, lot_id, slot) values (v_user, p_lot, k);
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'lot.bought', v_user, jsonb_build_object('lot', p_lot, 'n', v_n, 'cost', v_cost, 'deed', v_deed, 'cleanup_minutes', round(v_minutes::numeric, 1)));
  return public.farm_state(v_user);
end;
$$;
