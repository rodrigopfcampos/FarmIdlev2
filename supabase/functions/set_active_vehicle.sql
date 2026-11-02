-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.set_active_vehicle(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.vehicles where user_id = v_user and vehicle_id = p_vehicle) then raise exception 'veículo não é seu' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  update public.vehicles set active = (vehicle_id = p_vehicle) where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;
