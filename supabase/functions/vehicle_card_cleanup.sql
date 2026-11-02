-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.vehicle_card_cleanup(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.vehicles v set active = false
    where v.user_id = p_user and v.from_card is not null
      and not exists (select 1 from public.card_buffs b where b.user_id = p_user and b.serial = v.from_card);
  delete from public.vehicles v
    where v.user_id = p_user and v.from_card is not null
      and not exists (select 1 from public.card_buffs b where b.user_id = p_user and b.serial = v.from_card)
      and not exists (select 1 from public.expeditions x where x.user_id = p_user and x.vehicle_id = v.vehicle_id and x.status in ('travel', 'back'));
  -- sem veículo ativo, a Carroça volta a ser o ativo
  if not exists (select 1 from public.vehicles where user_id = p_user and active) then
    update public.vehicles set active = true where user_id = p_user and vehicle_id = 'carroca';
  end if;
end;
$$;
