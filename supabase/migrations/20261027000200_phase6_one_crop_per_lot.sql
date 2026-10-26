-- Fase 6 (ajuste do vídeo de 26/10): 1 cultivo por lote também no servidor.
-- set_crop num canteiro vale para o lote inteiro; semente rara só do cultivo do lote;
-- lotes antigos com cultivos misturados passam a ter o cultivo da maioria (o que já está crescendo termina normalmente).

create or replace function public.set_crop(p_target text, p_crop text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_time double precision;
  c jsonb;
  n int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or length(p_target) > 8 or p_target !~ '^[A-Z][0-9]{0,2}(-[0-9]{1,2})?$' then
    raise exception 'canteiro não encontrado' using errcode = 'check_violation';
  end if;
  -- 1 cultivo por lote: escolher num canteiro vale para o lote inteiro
  p_target := split_part(p_target, '-', 1);
  perform public.touch_farm(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  if p_crop is not null then
    c := public.crop_def(p_crop);
    if c is null or (c ->> 'kind') = 'orchard' then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
    if not public.crop_unlocked(v_user, c, public.team_fx(v_user)) then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  end if;
  update public.plots
    set crop_id = p_crop, stalled_reason = null,
        free_since = case when state = 'empty' then v_time else free_since end
    where user_id = v_user and (plot_id = p_target or plot_id like p_target || '-%')
      and split_part(plot_id, '-', 1) in (select lot_id from public.owned_lots where user_id = v_user);
  get diagnostics n = row_count;
  if n = 0 then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  if p_crop is not null then perform public.tend_plots(v_user, p_target, false, true); end if;
  return public.farm_state(v_user);
end;
$function$;

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

-- lotes com cultivos misturados: fica o cultivo escolhido na maioria dos canteiros (empate: o que está plantado em mais canteiros)
with mix as (
  select user_id, split_part(plot_id, '-', 1) lot from public.plots
  group by 1, 2 having count(distinct crop_id) > 1  -- canteiros sem cultivo continuam parados (não gasta semente sem o jogador pedir)
), pick as (
  select distinct on (p.user_id, m.lot) p.user_id, m.lot, p.crop_id
  from public.plots p join mix m on m.user_id = p.user_id and split_part(p.plot_id, '-', 1) = m.lot
  where p.crop_id is not null
  group by p.user_id, m.lot, p.crop_id
  order by p.user_id, m.lot, count(*) desc, count(*) filter (where p.state = 'growing') desc, p.crop_id
)
update public.plots p set crop_id = k.crop_id, stalled_reason = null
from pick k where p.user_id = k.user_id and split_part(p.plot_id, '-', 1) = k.lot and p.crop_id is not null and p.crop_id <> k.crop_id;
