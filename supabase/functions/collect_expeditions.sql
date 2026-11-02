-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.collect_expeditions(p_vehicle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); x public.expeditions; d text; v_list jsonb := '[]'; v_cards jsonb; v_serial bigint; cr public.cards;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  for x in select * from public.expeditions where user_id = v_user and status = 'back' and (p_vehicle is null or vehicle_id = p_vehicle)
           order by returns_at for update loop
    if x.gold > 0 then
      perform public.ledger_post(v_user, x.gold, 'exp_sale', jsonb_build_object('id', x.id, 'route', x.route_id, 'outcome', x.outcome), 'exp:' || x.id);
    end if;
    if x.refund > 0 then
      perform public.ledger_post(v_user, x.refund, 'exp_insurance_refund', jsonb_build_object('id', x.id, 'route', x.route_id), 'expref:' || x.id);
    end if;
    perform public.silo_add(v_user, x.cargo_back);
    -- achados: carta (v3) sorteada agora; achados antigos (itens, Kits, Escrituras) ainda entram no inventário
    v_cards := '[]';
    for d in select jsonb_array_elements_text(x.drops) loop
      if d = 'card' then
        v_serial := public.draw_card(v_user, 'expedition');
        select * into cr from public.cards where serial = v_serial;
        v_cards := v_cards || jsonb_build_array(jsonb_build_object('serial', v_serial, 'card_id', cr.card_id, 'rarity', cr.rarity));
      else
        insert into public.inventory (user_id, item_id, qty) values (v_user, d, 1)
          on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
      end if;
    end loop;
    update public.expeditions set status = 'collected', collected_at = now() where id = x.id;
    v_list := v_list || jsonb_build_object('id', x.id, 'vehicle_id', x.vehicle_id, 'route_id', x.route_id, 'seq', x.seq, 'outcome', x.outcome,
      'gold', x.gold, 'refund', x.refund, 'cargo', x.cargo, 'cargo_back', x.cargo_back, 'loss_frac', x.loss_frac, 'drops', x.drops, 'cards', v_cards,
      'report', x.report, 'insurance', x.insurance, 'minigame', x.minigame, 'chance', round(x.chance::numeric, 4));
  end loop;
  if v_list = '[]'::jsonb then raise exception 'nada para receber' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user) || jsonb_build_object('collected', v_list);
end;
$$;
