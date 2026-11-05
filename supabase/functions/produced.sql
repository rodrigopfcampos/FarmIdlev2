-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.produced(p_user uuid, p_item text, p_qty numeric, p_xp numeric, p_kind text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v numeric := coalesce(p_qty, 0) * coalesce(public.item_price(p_item), 0); at timestamptz := public.fx_at();
begin
  if coalesce(p_qty, 0) <= 0 then return; end if;
  perform public.prod_roll(p_user, public.user_day(p_user, at));
  update public.farms set prod_day_value = prod_day_value + v, prod_day_xp = prod_day_xp + coalesce(p_xp, 0) where user_id = p_user;
  -- Moeda da Sorte: % do valor do que foi produzido durante o buff
  update public.card_buffs set coin_value = coin_value + round(v * (public.card_def(card_id) -> 'buff_effects' -> rarity ->> 'production_gold_bonus_pct')::numeric / 100, 2)
    where user_id = p_user and started_at <= at and ends_at > at and public.card_def(card_id) -> 'buff_effects' -> rarity ? 'production_gold_bonus_pct';
  -- cartas por uso: 1 uso = um lote, pomar, casa de animais ou lago inteiro (config cards.rules.uses.units)
  perform public.card_use(p_user, p_kind, (public.config_get('cards') -> 'rules' -> 'uses' -> 'units' ->> p_kind)::numeric);
  perform public.mission_progress(p_user, 'xp_earned', p_xp);
  if p_kind = 'animal' then perform public.mission_progress(p_user, 'animal_products', p_qty);
  else perform public.mission_progress(p_user, 'harvest_value', v); end if;
end;
$$;
