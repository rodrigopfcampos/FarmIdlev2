-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
CREATE OR REPLACE FUNCTION public.rotate_team(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e jsonb := public.config_get('characters') -> 'energy';
  slots int := (public.config_get('characters') ->> 'field_slots')::int;
  c record; b record; n_field int;
begin
  if (select count(*) from public.characters where user_id = p_user) < (e ->> 'rotation_from_characters')::int then return; end if;
  for c in select ch.class_id, public.class_def(ch.class_id) ->> 'role' as role from public.characters ch
           where ch.user_id = p_user and ch.slot = 'field' and ch.leading_id is null and ch.energy <= (e ->> 'leave_field_at')::double precision order by ch.energy loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.leading_id is null and ch.energy >= (e ->> 'enter_field_at')::double precision
      order by (public.class_def(ch.class_id) ->> 'role' = c.role) desc, ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'bench', parked = false where user_id = p_user and class_id = c.class_id;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
  end loop;
  -- vaga livre no campo: entra quem está descansado
  select count(*) into n_field from public.characters where user_id = p_user and slot = 'field';
  while n_field < slots loop
    select ch.class_id into b from public.characters ch
      where ch.user_id = p_user and ch.slot = 'bench' and ch.leading_id is null and ch.energy >= (e ->> 'enter_field_at')::double precision order by ch.energy desc limit 1;
    exit when not found;
    update public.characters set slot = 'field', parked = false where user_id = p_user and class_id = b.class_id;
    n_field := n_field + 1;
  end loop;
end;
$function$;
