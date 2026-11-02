-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.tend_plots(p_user uuid, p_target text, p_harvest boolean, p_plant boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_time double precision; fx jsonb := public.team_fx(p_user);
  v_gold numeric; v_seed_spent numeric := 0; v_refund numeric := 0; v_plantings int := 0; v_seed numeric; v_feed numeric := 0; v_f numeric;
  r record;
begin
  select farm_time into v_time from public.farms where user_id = p_user for update;
  if p_harvest then
    for r in select pl.plot_id from public.plots pl
             where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      v_refund := v_refund + public.harvest_plot(p_user, r.plot_id, v_time, fx);
    end loop;
    for r in select t.lot_id, t.slot from public.trees t
             where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= v_time
               and (p_target is null or t.lot_id = p_target)
             order by t.lot_id, t.slot loop
      perform public.harvest_tree(p_user, r.lot_id, r.slot, v_time, fx);
    end loop;
    if v_refund > 0 then perform public.ledger_post(p_user, round(v_refund, 2), 'seed_refund', jsonb_build_object('by', 'player')); end if;
    -- animais prontos: o clique coleta a 100% e começa o próximo ciclo (cobra a ração)
    select gold into v_gold from public.wallets where user_id = p_user;
    for r in select a.house_id, a.slot from public.animals a
             where a.user_id = p_user and a.state = 'growing' and a.ready_at <= v_time
               and (p_target is null or p_target = public.house_lot(a.house_id))
             order by a.house_id, a.slot loop
      perform public.animal_collect(p_user, r.house_id, r.slot, v_time, fx, false);
      v_f := public.animal_start(p_user, r.house_id, r.slot, v_time, fx, v_gold - v_feed);
      v_feed := v_feed + coalesce(v_f, 0);
    end loop;
    if v_feed > 0 then perform public.ledger_post(p_user, -round(v_feed, 2), 'feed', jsonb_build_object('by', 'player')); end if;
  end if;
  if p_plant then
    select gold into v_gold from public.wallets where user_id = p_user for update;
    for r in select pl.plot_id, pl.crop_id from public.plots pl
             join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
             where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and ol.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      v_seed := public.seed_price(r.crop_id, fx);
      if v_gold - v_seed_spent < v_seed then
        update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = r.plot_id;
        continue;
      end if;
      v_seed_spent := v_seed_spent + public.plant_plot(p_user, r.plot_id, r.crop_id, v_time, fx);
      v_plantings := v_plantings + 1;
    end loop;
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds',
        jsonb_build_object('plantings', v_plantings, 'farm_time', round(v_time::numeric, 1), 'by', 'player'));
    end if;
  end if;
end;
$$;
