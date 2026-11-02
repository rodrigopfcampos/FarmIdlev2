-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.hire(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid(); d jsonb := public.class_def(p_class); v_level int; v_cost numeric; v_field int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if d is null then raise exception 'personagem não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem já contratado' using errcode = 'check_violation';
  end if;
  select level into v_level from public.farms where user_id = v_user;
  if v_level < (d ->> 'unlock_level')::int then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_cost := round((public.config_get('characters') -> 'hire_cost' ->> 'multiplier')::numeric * public.ref_income((d ->> 'unlock_level')::int), 2);
  if v_cost > 0 then perform public.ledger_post(v_user, -v_cost, 'hire', jsonb_build_object('class', p_class), 'hire:' || p_class); end if;
  select count(*) into v_field from public.characters where user_id = v_user and slot = 'field';
  insert into public.characters (user_id, class_id, slot) values (v_user, p_class,
    case when v_field < (public.config_get('characters') ->> 'field_slots')::int then 'field' else 'bench' end);
  insert into public.tools (user_id, class_id) values (v_user, p_class) on conflict do nothing;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'character.hired', v_user, jsonb_build_object('class', p_class, 'cost', v_cost));
  return public.farm_state(v_user);
end;
$$;
