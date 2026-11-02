-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_state(p_user uuid)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'vehicles', (select coalesce(jsonb_agg(jsonb_build_object('vehicle_id', v.vehicle_id, 'rarity', v.rarity, 'durability', round(v.durability::numeric, 2),
        'active', v.active, 'refurb_rarity', v.refurb_rarity, 'refurb_until', v.refurb_until) order by v.bought_at), '[]')
      from public.vehicles v where v.user_id = p_user),
    'expeditions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'convoy_id', x.convoy_id, 'vehicle_id', x.vehicle_id, 'route_id', x.route_id,
        'cargo', x.cargo, 'insurance', x.insurance, 'led', x.led, 'minigame', x.minigame, 'started_at', x.started_at, 'returns_at', x.returns_at,
        'seq', x.seq, 'repeat_left', x.repeat_left, 'status', x.status) order by x.started_at), '[]')
      from public.expeditions x where x.user_id = p_user and x.status in ('travel', 'back')),
    'exp_fail_streak', (select exp_fail_streak from public.farms where user_id = p_user),
    'lead', public.lead_info(p_user),
    'demand', (select coalesce(jsonb_object_agg(d.route_id, d.products), '{}') from public.daily_demand d where d.day = public.game_day(now())),
    'demand_tomorrow', case when (public.team_fx(p_user) ->> 'route_preview')::double precision > 0
      then (select coalesce(jsonb_object_agg(d.route_id, d.products), '{}') from public.daily_demand d where d.day = public.game_day(now()) + 1) end)
$$;
