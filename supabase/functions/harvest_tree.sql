-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.harvest_tree(p_user uuid, p_lot text, p_slot integer, p_t double precision, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tr public.trees; c jsonb; m double precision; rm double precision; v_qty int;
begin
  select * into tr from public.trees where user_id = p_user and lot_id = p_lot and slot = p_slot for update;
  c := public.crop_def(tr.fruit_id);
  rm := case when tr.rare_left > 0 then public.rarity_mult(tr.rarity) else 1 end;
  m := rm;
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  if public.rand01() < coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- Mutação Genética
  m := m * (1 + coalesce((fx ->> 'yield')::double precision, 0));  -- Cesta
  v_qty := public.round_rand((c ->> 'units_per_harvest')::double precision * m);
  if public.rand01() < (fx ->> 'extra_fruit')::double precision then v_qty := v_qty + 1; end if;
  insert into public.silo (user_id, item_id, qty) values (p_user, tr.fruit_id, v_qty)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.produced(p_user, tr.fruit_id, v_qty, (c ->> 'xp_per_harvest')::numeric * rm::numeric, 'orchard');
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, tr.fruit_id, fx);
  update public.trees set ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_orchard')::double precision),
      rare_left = greatest(0, rare_left - 1), rarity = case when rare_left <= 1 then null else rarity end
    where user_id = p_user and lot_id = p_lot and slot = p_slot;
end;
$function$;
