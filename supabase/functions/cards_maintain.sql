-- versão atual (veio de supabase/migrations/20261103000100_v3_card_supply.sql)
create or replace function public.cards_maintain(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare c public.cards; v_free int; v numeric;
begin
  perform public.cards_starter(p_user);
  for c in select * from public.cards where user_id = p_user and state = 'inbox' and inbox_until <= now() order by serial for update loop
    v := public.collector_price(p_user, c.rarity);
    update public.cards set state = 'sold', changed_at = now() where serial = c.serial;
    if v > 0 then perform public.ledger_post(p_user, v, 'card_sale', jsonb_build_object('serial', c.serial, 'card', c.card_id, 'rarity', c.rarity, 'auto', true), 'card:' || c.serial); end if;
  end loop;
  select f.binder_slots - (select count(*) from public.cards where user_id = p_user and state in ('binder', 'worn')) into v_free from public.farms f where f.user_id = p_user;
  if v_free > 0 then
    update public.cards set state = 'binder', inbox_until = null, changed_at = now()
      where serial in (select serial from public.cards where user_id = p_user and state = 'inbox' order by serial limit v_free);
  end if;
  perform public.vehicle_card_cleanup(p_user);
end;
$$;
