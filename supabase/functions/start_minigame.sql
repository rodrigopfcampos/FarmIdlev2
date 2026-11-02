-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.start_minigame(p_route text, p_vehicles int, p_manager boolean, p_calm boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); m jsonb := public.config_get('expeditions') -> 'minigame'; n int; secs double precision; arr text[]; k int; v_id uuid;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.exp_route(p_route) is null then raise exception 'rota não existe' using errcode = 'check_violation'; end if;
  if p_vehicles is null or p_vehicles < 1 or p_vehicles > 4 then raise exception 'número de veículos inválido' using errcode = 'check_violation'; end if;
  n := (m -> 'arrows' ->> p_route)::int + (m ->> 'convoy_extra_arrows')::int * (p_vehicles - 1);
  secs := (m -> 'seconds' ->> p_route)::double precision + (m ->> 'convoy_extra_seconds')::double precision * (p_vehicles - 1)
          + case when coalesce(p_manager, false) then (m ->> 'manager_extra_seconds')::double precision else 0 end;
  if coalesce(p_calm, false) then secs := secs * (m ->> 'calm_mode_time_multiplier')::double precision; end if;
  for k in 1 .. n loop
    arr := arr || ((m -> 'arrows_pool') ->> floor(public.rand01() * jsonb_array_length(m -> 'arrows_pool'))::int);
  end loop;
  insert into public.minigames (user_id, route_id, vehicles, manager, calm, arrows, limit_ms)
    values (v_user, p_route, p_vehicles, coalesce(p_manager, false), coalesce(p_calm, false), arr, round(secs * 1000)::int)
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'arrows', to_jsonb(arr), 'limit_ms', round(secs * 1000)::int);
end;
$$;
