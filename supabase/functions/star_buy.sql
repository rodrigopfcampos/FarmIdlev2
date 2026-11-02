-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.star_buy(p_kind text, p_crop text default null, p_rarity text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); s jsonb := public.config_get('village') -> 'stars'; f public.farms; wk date; v_stars int; v_gold numeric; p jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  if f.level < (s ->> 'unlock_level')::int then raise exception 'estrelas liberam no nível 50' using errcode = 'check_violation'; end if;
  wk := public.mission_week(public.user_day(v_user, now()));
  if p_kind = 'pack' then
    p := s -> 'pack';
    if (select count(*) from public.star_purchases where user_id = v_user and week = wk and kind = 'pack') >= (p ->> 'per_week')::int then
      raise exception 'limite da semana atingido' using errcode = 'check_violation';
    end if;
  elsif p_kind = 'seed' then
    p := s -> 'seed' -> 'rarities' -> p_rarity;
    if p is null then raise exception 'raridade inválida' using errcode = 'check_violation'; end if;
    if public.crop_def(p_crop) is null then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
    if (select count(*) from public.star_purchases where user_id = v_user and week = wk and kind = 'seed') >= (s -> 'seed' ->> 'per_week')::int then
      raise exception 'limite da semana atingido' using errcode = 'check_violation';
    end if;
  else
    raise exception 'compra inválida' using errcode = 'check_violation';
  end if;
  v_stars := (p ->> 'stars')::int;
  v_gold := round(public.ref_income(f.level) * (p ->> 'gold_R_ratio')::numeric, 2);
  if f.stars < v_stars then raise exception 'estrelas insuficientes' using errcode = 'check_violation'; end if;
  perform public.ledger_post(v_user, -v_gold, 'star_shop', jsonb_build_object('kind', p_kind, 'crop', p_crop, 'rarity', p_rarity, 'stars', v_stars));
  update public.farms set stars = stars - v_stars where user_id = v_user;
  insert into public.star_purchases (user_id, week, kind, crop_id, rarity, stars, gold) values (v_user, wk, p_kind, p_crop, p_rarity, v_stars, v_gold);
  if p_kind = 'pack' then
    perform public.draw_card(v_user, 'estrelas');
  else
    insert into public.inventory (user_id, item_id, qty) values (v_user, 'seed:' || p_crop || ':' || p_rarity, 1)
      on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
  end if;
  return public.village_state(v_user);
end;
$$;
