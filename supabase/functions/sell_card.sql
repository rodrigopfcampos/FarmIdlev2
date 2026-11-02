-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.sell_card(p_serial bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); c public.cards; v numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.cards where serial = p_serial and user_id = v_user and state in ('binder', 'inbox', 'worn') for update;
  if not found then raise exception 'carta não encontrada' using errcode = 'check_violation'; end if;
  v := public.collector_price(v_user, c.rarity);
  update public.cards set state = 'sold', seen = true, changed_at = now() where serial = c.serial;
  perform public.ledger_post(v_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity), 'card:' || c.serial);
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;
