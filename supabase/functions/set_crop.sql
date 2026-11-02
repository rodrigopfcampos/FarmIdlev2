-- versão atual (veio de supabase/migrations/20261027000200_phase6_one_crop_per_lot.sql)
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
