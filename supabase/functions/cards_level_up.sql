-- versão atual (veio de supabase/migrations/20261103000100_v3_card_supply.sql)
create or replace function public.cards_level_up(p_user uuid, p_level int)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare l jsonb := public.config_get('cards') -> 'rules' -> 'supply' -> 'level_up_cards'; v_to int; lv int; k int;
begin
  if current_setting('vif.missions', true) = 'off' or l is null then return; end if;
  select level_cards_to into v_to from public.farms where user_id = p_user for update;
  for lv in greatest(v_to + 1, (l ->> 'from_level')::int) .. least(p_level, (l ->> 'to_level')::int) loop
    for k in 1 .. (l ->> 'cards_per_level')::int loop perform public.draw_card(p_user, 'level_up'); end loop;
  end loop;
  update public.farms set level_cards_to = greatest(level_cards_to, p_level) where user_id = p_user;
end;
$$;
