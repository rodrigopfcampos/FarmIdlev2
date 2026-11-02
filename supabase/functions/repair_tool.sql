-- versão atual (veio de supabase/migrations/20261106000100_v3_r3_fishing_tree.sql)
create or replace function public.repair_tool(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_mat text; v_dur double precision; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select material, durability into v_mat, v_dur from public.tools where user_id = v_user and class_id = p_class for update;
  if v_mat is null then raise exception 'ferramenta não encontrada' using errcode = 'check_violation'; end if;
  if v_dur >= 100 then raise exception 'ferramenta já está inteira' using errcode = 'check_violation'; end if;
  v_cost := round((public.material_def(v_mat) ->> 'repair_cost_gold')::numeric * (1 + (public.team_fx(v_user) ->> 'tool_cost')::numeric)
            * (1 - (public.team_fx(v_user) ->> 'repair_cut')::numeric), 2);
  perform public.ledger_post(v_user, -v_cost, 'tool_repair', jsonb_build_object('class', p_class, 'material', v_mat, 'durability', round(v_dur::numeric, 1)));
  update public.tools set durability = 100 where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;
