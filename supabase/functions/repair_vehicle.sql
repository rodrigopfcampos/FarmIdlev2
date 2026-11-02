-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.repair_vehicle(p_vehicle text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v public.vehicles; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into v from public.vehicles where user_id = v_user and vehicle_id = p_vehicle for update;
  if not found then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
  if v.durability >= 100 then raise exception 'veículo já está inteiro' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.expeditions where user_id = v_user and vehicle_id = p_vehicle and status = 'travel') then
    raise exception 'veículo está viajando' using errcode = 'check_violation';
  end if;
  v_cost := round(public.vehicle_price(p_vehicle) * (public.config_get('expeditions') -> 'vehicle_repair' ->> 'cost_ratio_of_price')::numeric
            * (100 - v.durability)::numeric / 100 * (1 - (public.team_fx(v_user) ->> 'repair_cut')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'vehicle_repair', jsonb_build_object('vehicle', p_vehicle, 'durability', round(v.durability::numeric, 1)));
  update public.vehicles set durability = 100 where user_id = v_user and vehicle_id = p_vehicle;
  perform public.mission_progress(v_user, 'vehicle_repair', 1);
  return public.farm_state(v_user);
end;
$function$;
