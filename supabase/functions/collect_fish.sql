-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.collect_fish()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_t double precision;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select farm_time into v_t from public.farms where user_id = v_user;
  if not public.lake_ready(v_user, v_t) then raise exception 'compre o Lago para pescar' using errcode = 'check_violation'; end if;
  if public.fish_collect(v_user, v_t, public.team_fx(v_user), false) = 0 then raise exception 'a rede ainda está vazia' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;
