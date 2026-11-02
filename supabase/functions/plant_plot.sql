-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.plant_plot(p_user uuid, p_plot text, p_crop text, p_t double precision, fx jsonb, p_rarity text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c jsonb := public.crop_def(p_crop); v_seed numeric;
begin
  v_seed := case when p_rarity is null then round((c ->> 'seed_cost')::numeric * (1 - (fx ->> 'seed_discount')::numeric), 2) else 0 end;
  update public.plots
    set state = 'growing', planted_crop_id = p_crop, planted_kind = c ->> 'kind', planted_at = p_t, harvests_done = 0,
        ready_at = case when public.rand01() < coalesce((fx ->> 'instant_growth')::double precision, 0) then p_t  -- Mão Verde: nasce pronta
                        else p_t + (c ->> 'grow_minutes')::double precision * 60 / (1 + (fx ->> 'growth_crop')::double precision) end,
        free_since = null, stalled_reason = null, rarity = p_rarity, seed_paid = v_seed
    where user_id = p_user and plot_id = p_plot;
  -- missão "plante um cultivo dos seus últimos níveis"
  if (c ->> 'unlock_level')::int >= (select level from public.farms where user_id = p_user) - (public.config_get('missions') ->> 'plant_top_window_levels')::int then
    perform public.mission_progress(p_user, 'plant_top', 1);
  end if;
  return v_seed;
end;
$function$;
