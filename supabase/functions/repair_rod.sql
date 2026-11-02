-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.repair_rod()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_cost numeric; v_dur double precision;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select rod_durability into v_dur from public.farms where user_id = v_user for update;
  if v_dur >= 100 then raise exception 'a vara já está inteira' using errcode = 'check_violation'; end if;
  v_cost := public.rod_repair_cost(v_user);
  perform public.ledger_post(v_user, -v_cost, 'rod_repair', jsonb_build_object('durability', round(v_dur::numeric, 1)));
  update public.farms set rod_durability = 100 where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;
