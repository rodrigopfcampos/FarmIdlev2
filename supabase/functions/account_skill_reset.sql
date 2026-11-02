-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.account_skill_reset()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); f public.farms; v_week text := to_char(public.game_day(now()), 'IYYY-IW'); v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  if f.account_skills = '{}'::jsonb then raise exception 'nada para resetar' using errcode = 'check_violation'; end if;
  if f.account_reset_week is distinct from v_week then
    update public.farms set account_reset_week = v_week where user_id = v_user;
  else
    v_cost := round(public.ref_income(f.level) * (public.config_get('characters') -> 'account_tree' ->> 'extra_reset_cost_R_ratio')::numeric, 2);
    perform public.ledger_post(v_user, -v_cost, 'skill_reset', jsonb_build_object('tree', 'account'));
  end if;
  update public.farms set account_skills = '{}'::jsonb where user_id = v_user;
  return public.farm_state(v_user);
end;
$$;
