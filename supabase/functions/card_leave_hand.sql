-- versão atual (veio de supabase/migrations/20261105000100_v3_hand_split.sql)
create or replace function public.card_leave_hand(p_user uuid, b public.card_buffs, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_left double precision := greatest(0, extract(epoch from (b.ends_at - p_at)));
  v_room boolean := public.hand_count(p_user) < public.hand_slots((select level from public.farms where user_id = p_user))
    and not exists (select 1 from public.cards where user_id = p_user and card_id = b.card_id and state = 'hand');
begin
  if b.coin_value > 0 then
    perform public.ledger_post(p_user, b.coin_value, 'lucky_coin', jsonb_build_object('serial', b.serial, 'rarity', b.rarity), 'coin:' || b.serial || ':' || extract(epoch from p_at));
  end if;
  delete from public.card_buffs where user_id = p_user and card_id = b.card_id;
  update public.cards set life_seconds = v_left, changed_at = now(),
      state = case when v_left > 0 and v_room then 'hand' when v_left > 0 then 'binder' when rarity = 'common' then 'worn' else 'used' end
    where serial = b.serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, case when v_left > 0 then 'card.unequipped' else 'card.worn_out' end, p_user, jsonb_build_object('serial', b.serial, 'card', b.card_id, 'rarity', b.rarity, 'left_s', round(v_left::numeric)));
  if b.card_id = 'veiculo' then perform public.vehicle_card_cleanup(p_user); end if;
end;
$$;
