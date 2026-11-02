-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.set_slot(p_class text, p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_field int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_slot not in ('field', 'bench') then raise exception 'slot inválido' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and class_id = p_class) then
    raise exception 'personagem não contratado' using errcode = 'check_violation';
  end if;
  if p_slot = 'field' then
    select count(*) into v_field from public.characters where user_id = v_user and slot = 'field' and class_id <> p_class;
    if v_field >= (public.config_get('characters') ->> 'field_slots')::int then raise exception 'campo cheio' using errcode = 'check_violation'; end if;
  end if;
  update public.characters set slot = p_slot where user_id = v_user and class_id = p_class;
  return public.farm_state(v_user);
end;
$$;
