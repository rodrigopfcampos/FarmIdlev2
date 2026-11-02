-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.help_lot(p_target uuid, p_lot text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); cfg jsonb := public.config_get('social') -> 'help'; dv date; dt date; l public.owned_lots; v_t double precision;
  v_kind text; v_pct numeric; v_ferreiro double precision; v_xp numeric; v_type text; v_ends timestamptz;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  perform public.advance_farm(p_target, now());
  dv := public.user_day(v_user, now()); dt := public.user_day(p_target, now());
  -- trava a fazenda de quem ajuda (limite diário) e a do dono (limite recebido e um por lote)
  perform 1 from public.farms where user_id in (v_user, p_target) order by user_id for update;
  if (select count(*) from public.lot_helps where helper = v_user and given_day = dv) >= (cfg ->> 'given_per_day')::int then
    raise exception 'ajudas de hoje acabaram' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.lot_helps where owner = p_target and received_day = dt) >= (cfg ->> 'received_per_day')::int then
    raise exception 'essa fazenda já recebeu todas as ajudas de hoje' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.lot_helps where owner = p_target and lot_id = p_lot and started_at > now() - make_interval(mins => (cfg ->> 'lot_cooldown_minutes')::int)) then
    raise exception 'esse lote já foi ajudado há pouco' using errcode = 'check_violation';
  end if;
  select * into l from public.owned_lots where user_id = p_target and lot_id = p_lot for update;
  if not found then raise exception 'lote não encontrado' using errcode = 'check_violation'; end if;
  select farm_time into v_t from public.farms where user_id = p_target;
  v_type := public.lot_def(p_lot) ->> 'type';
  if l.ready_at > v_t then
    v_kind := 'cleanup';
  elsif v_type in ('lavoura', 'pomar')
        and (exists (select 1 from public.plots where user_id = p_target and split_part(plot_id, '-', 1) = p_lot and state = 'growing')
             or exists (select 1 from public.trees where user_id = p_target and lot_id = p_lot and fruit_id is not null)) then
    v_kind := 'growth';
  else
    raise exception 'nada para ajudar nesse lote' using errcode = 'check_violation';
  end if;
  -- Ferreiro em campo na fazenda do dono (Obras B): +10% por ponto no efeito
  select coalesce(sum(public.skill_effect(ch.class_id, ch.skills, 'neighbor_help_pct')), 0) into v_ferreiro
    from public.characters ch where ch.user_id = p_target and public.char_active(ch);
  v_pct := round(((case when v_kind = 'growth' then cfg ->> 'growth_pct' else cfg ->> 'cleanup_pct' end)::numeric * (1 + v_ferreiro::numeric / 100)), 2);
  if v_kind = 'cleanup' then
    update public.owned_lots set ready_at = v_t + (ready_at - v_t) * (1 - v_pct::double precision / 100) where user_id = p_target and lot_id = p_lot;
    v_ends := now() + make_interval(mins => (cfg ->> 'lot_cooldown_minutes')::int);
  else
    v_ends := now() + make_interval(mins => (cfg ->> 'growth_minutes')::int);
  end if;
  v_xp := round(((public.prod_ref(v_user) ->> 'xp_h')::numeric * (cfg ->> 'xp_minutes_of_production')::numeric / 60), 2);
  insert into public.lot_helps (owner, helper, lot_id, kind, pct, started_at, ends_at, given_day, received_day, xp)
    values (p_target, v_user, p_lot, v_kind, v_pct, now(), v_ends, dv, dt, v_xp);
  if v_xp > 0 then perform public.add_xp(v_user, v_xp); end if;
  perform public.mission_progress(v_user, 'neighbors_helped', 1);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'social.help', p_target, jsonb_build_object('lot', p_lot, 'kind', v_kind, 'pct', v_pct, 'xp', v_xp));
  return public.visit_view(v_user, p_target);
end;
$$;
