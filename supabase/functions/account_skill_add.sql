-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.account_skill_add(p_node text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); nd jsonb := public.account_node(p_node); f public.farms; v_cur int; r jsonb; ok boolean;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if nd is null then raise exception 'habilidade não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  v_cur := coalesce((f.account_skills ->> p_node)::int, 0);
  if v_cur >= (nd ->> 'max')::int then raise exception 'habilidade no máximo' using errcode = 'check_violation'; end if;
  if public.account_spent(v_user) + (nd ->> 'cost')::int > public.account_points(v_user) then raise exception 'sem pontos de habilidade' using errcode = 'check_violation'; end if;
  -- caminho: todos os "requires", ao menos um dos "requires_any" e os pontos do ramo
  for r in select jsonb_array_elements(coalesce(nd -> 'requires', '[]')) loop
    if coalesce((f.account_skills ->> (r ->> 'node'))::int, 0) < (r ->> 'min')::int then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  end loop;
  if nd ? 'requires_any' then
    select bool_or(coalesce((f.account_skills ->> (x ->> 'node'))::int, 0) >= (x ->> 'min')::int) into ok from jsonb_array_elements(nd -> 'requires_any') x;
    if not ok then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  end if;
  if public.account_spent(v_user, nd ->> 'branch') < coalesce((nd ->> 'requires_branch_points')::int, 0) then raise exception 'passiva bloqueada' using errcode = 'check_violation'; end if;
  update public.farms set account_skills = account_skills || jsonb_build_object(p_node, v_cur + 1) where user_id = v_user;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'skill.add', v_user, jsonb_build_object('node', p_node, 'to', v_cur + 1));
  return public.farm_state(v_user);
end;
$$;
