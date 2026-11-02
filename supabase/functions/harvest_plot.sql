-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.harvest_plot(p_user uuid, p_plot text, p_t double precision, fx jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_q int; pl public.plots; c jsonb; v_done int; v_total int; m double precision; rm double precision; v_refund numeric := 0;
begin
  select * into pl from public.plots where user_id = p_user and plot_id = p_plot for update;
  c := public.crop_def(pl.planted_crop_id);
  rm := public.rarity_mult(pl.rarity);
  m := rm * (1 + case when c ->> 'kind' = 'recurring' then (fx ->> 'recurring')::double precision else 0 end);
  if public.rand01() < (fx ->> 'golden')::double precision then m := m * (fx ->> 'golden_mult')::double precision; end if;
  if c ->> 'kind' = 'crop' and public.rand01() < (fx ->> 'double_crop')::double precision then m := m * 2; end if;
  if public.rand01() < coalesce((fx ->> 'mutation')::double precision, 0) then m := m * 2; end if;  -- Mutação Genética
  m := m * (1 + coalesce((fx ->> 'yield')::double precision, 0));  -- Cesta
  v_q := public.round_rand((c ->> 'units_per_harvest')::double precision * m);
  insert into public.silo (user_id, item_id, qty) values (p_user, pl.planted_crop_id, v_q)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.produced(p_user, pl.planted_crop_id, v_q, (c ->> 'xp_per_harvest')::numeric * rm::numeric, 'crop');
  perform public.add_xp(p_user, round(((c ->> 'xp_per_harvest')::numeric * rm::numeric
    * (1 + (fx ->> 'harvest_xp')::numeric) * (1 + (fx ->> 'account_xp')::numeric)), 2));
  perform public.roll_rare_seed(p_user, pl.planted_crop_id, fx);
  v_done := pl.harvests_done + 1;
  v_total := coalesce((c ->> 'harvests_per_planting')::int, 1);
  if (c ->> 'kind') = 'recurring' and v_done < v_total then
    update public.plots set harvests_done = v_done,
        ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision)
      where user_id = p_user and plot_id = p_plot;
  else
    if pl.seed_paid > 0 and public.rand01() < (fx ->> 'seed_refund')::double precision then v_refund := pl.seed_paid; end if;
    update public.plots set state = 'empty', planted_crop_id = null, planted_kind = null, planted_at = null, ready_at = null,
        harvests_done = 0, free_since = p_t, rarity = null, seed_paid = 0
      where user_id = p_user and plot_id = p_plot;
  end if;
  return v_refund;
end;
$function$;
