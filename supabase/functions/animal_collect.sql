-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.animal_collect(p_user uuid, p_house text, p_slot integer, p_t double precision, fx jsonb, p_team boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.animals; d jsonb; r jsonb := public.config_get('animals') -> 'rules'; m double precision; bonus double precision; v_qty int;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  d := public.animal_def(a.animal_id);
  bonus := coalesce((fx ->> 'animal_production')::double precision, 0)
         + case when (d ->> 'is_bird')::boolean then coalesce((fx ->> 'bird_bonus')::double precision, 0) else 0 end;
  m := public.rarity_mult(a.rarity) * (1 + least(bonus, coalesce((fx ->> 'animal_cap')::double precision, 0.6)))
     * case when p_team then case when coalesce((fx ->> 'rancheira')::boolean, false) then (r -> 'collector_efficiency' ->> 'rancheira')::double precision
                                  else (r -> 'collector_efficiency' ->> 'other_class')::double precision end else 1 end;
  if public.rand01() < coalesce((fx ->> 'animal_double')::double precision, 0) + coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- + Mutação Genética
  v_qty := public.round_rand(coalesce((r ->> 'units_per_collect')::double precision, 1) * m);
  if v_qty > 0 then
    insert into public.silo (user_id, item_id, qty) values (p_user, d -> 'product' ->> 'id', v_qty)
      on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
    perform public.produced(p_user, d -> 'product' ->> 'id', v_qty, (d ->> 'xp_per_collect')::numeric, 'animal');
  end if;
  perform public.add_xp(p_user, round((d ->> 'xp_per_collect')::numeric * (1 + (fx ->> 'account_xp')::numeric), 2));
  update public.animals set ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_qty;
end;
$function$;
