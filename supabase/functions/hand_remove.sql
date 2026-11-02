-- versão atual (veio de supabase/migrations/20261104000100_v3_hand_use.sql)
create or replace function public.hand_remove(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state = 'hand' for update;
  if not found then raise exception 'essa carta não está parada na mão' using errcode = 'check_violation'; end if;
  if (select count(*) from public.cards where user_id = v_user and state in ('binder', 'worn')) >= (select binder_slots from public.farms where user_id = v_user) then
    raise exception 'o fichário está cheio' using errcode = 'check_violation';
  end if;
  update public.cards set state = 'binder', changed_at = now() where serial = c.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'card.from_hand', v_user, jsonb_build_object('serial', c.serial, 'card', c.card_id));
  return public.farm_state(v_user);
end;
$$;
