-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.plant_tree(p_lot text, p_slot int, p_fruit text, p_rarity text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  c jsonb := public.crop_def(p_fruit);
  v_time double precision; v_ready double precision; v_cost numeric; fx jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if c is null or (c ->> 'kind') <> 'orchard' then raise exception 'fruta inválida' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  fx := public.team_fx(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  if p_rarity is null and not public.crop_unlocked(v_user, c, fx) then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  select ready_at into v_ready from public.owned_lots where user_id = v_user and lot_id = p_lot;
  if v_ready is null or not exists (select 1 from public.trees where user_id = v_user and lot_id = p_lot and slot = p_slot) then
    raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation';
  end if;
  if v_ready > v_time then raise exception 'lote ainda em limpeza' using errcode = 'check_violation'; end if;
  if p_rarity is not null then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'seed:' || p_fruit || ':' || p_rarity and qty >= 1;
    if not found then raise exception 'semente rara não encontrada' using errcode = 'check_violation'; end if;
  else
    v_cost := (c ->> 'sapling_cost')::numeric;
    perform public.ledger_post(v_user, -v_cost, 'sapling', jsonb_build_object('lot', p_lot, 'slot', p_slot, 'fruit', p_fruit));
  end if;
  update public.trees set fruit_id = p_fruit, planted_at = v_time,
      ready_at = v_time + (c ->> 'grow_minutes')::double precision * 60 * (1 + (fx ->> 'tree_initial')::double precision) / (1 + (fx ->> 'growth_orchard')::double precision),
      rarity = p_rarity, rare_left = case when p_rarity is null then 0 else coalesce((public.config_get('rarity') -> 'seeds' ->> 'tree_harvests')::int, 6) end
    where user_id = v_user and lot_id = p_lot and slot = p_slot;
  return public.farm_state(v_user);
end;
$$;
