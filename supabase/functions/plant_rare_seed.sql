-- versão atual (veio de supabase/migrations/20261027000200_phase6_one_crop_per_lot.sql)
create or replace function public.plant_rare_seed(p_plot text, p_crop text, p_rarity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_time double precision; pl public.plots; v_ready double precision; c jsonb := public.crop_def(p_crop);
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if c is null or c ->> 'kind' = 'orchard' then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  select * into pl from public.plots where user_id = v_user and plot_id = p_plot for update;
  if not found then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  select ready_at into v_ready from public.owned_lots where user_id = v_user and lot_id = split_part(p_plot, '-', 1);
  if v_ready > v_time then raise exception 'lote ainda em limpeza' using errcode = 'check_violation'; end if;
  -- a semente rara tem de ser do cultivo escolhido para o lote (1 cultivo por lote)
  if not exists (select 1 from public.plots where user_id = v_user and plot_id like split_part(p_plot, '-', 1) || '-%' and crop_id = p_crop)
     or exists (select 1 from public.plots where user_id = v_user and plot_id like split_part(p_plot, '-', 1) || '-%' and crop_id <> p_crop) then
    raise exception 'semente de outro cultivo' using errcode = 'check_violation';
  end if;
  if pl.state = 'growing' and pl.ready_at <= v_time then perform public.tend_plots(v_user, p_plot, true, false); end if;
  if (select state from public.plots where user_id = v_user and plot_id = p_plot) <> 'empty' then
    raise exception 'canteiro ocupado' using errcode = 'check_violation';
  end if;
  update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'seed:' || p_crop || ':' || p_rarity and qty >= 1;
  if not found then raise exception 'semente rara não encontrada' using errcode = 'check_violation'; end if;
  update public.plots set crop_id = p_crop where user_id = v_user and plot_id = p_plot;
  perform public.plant_plot(v_user, p_plot, p_crop, v_time, public.team_fx(v_user), p_rarity);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'seed.rare_planted', v_user, jsonb_build_object('plot', p_plot, 'crop', p_crop, 'rarity', p_rarity));
  return public.farm_state(v_user);
end;
$function$;
