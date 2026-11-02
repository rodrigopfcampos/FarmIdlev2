-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.unequip_card(p_card text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); b public.card_buffs;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into b from public.card_buffs where user_id = v_user and card_id = p_card for update;
  if not found then raise exception 'essa carta não está na mão' using errcode = 'check_violation'; end if;
  if b.locked_until is not null and b.locked_until > now() then raise exception 'a carta ainda está presa na mão' using errcode = 'check_violation'; end if;
  perform public.card_leave_hand(v_user, b, now());
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;
