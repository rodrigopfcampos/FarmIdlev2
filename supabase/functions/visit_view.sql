-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.visit_view(p_viewer uuid, p_target uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  st jsonb := public.farm_state(p_target); cfg jsonb := public.config_get('social'); dv date := public.user_day(p_viewer, now()); dt date := public.user_day(p_target, now());
begin
  return jsonb_build_object(
    'owner', public.player_card(p_target) || jsonb_build_object('status', public.friend_status(p_viewer, p_target)),
    'state', (select jsonb_object_agg(key, value) from jsonb_each(st) where key = any (array['server_now', 'game_day', 'weather', 'farm_time', 'synced_at',
        'last_activity_at', 'offline_cap_hours', 'nickname', 'level', 'lots', 'plots', 'trees', 'animals', 'houses', 'lake', 'pet']))
      || jsonb_build_object('helps', st -> 'social' -> 'helps',
        'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p ->> 'pet_id', 'active', true)), '[]') from jsonb_array_elements(st -> 'pets') p where (p ->> 'active')::boolean),
        'vehicles', (select coalesce(jsonb_agg(jsonb_build_object('vehicle_id', v ->> 'vehicle_id', 'rarity', v ->> 'rarity', 'active', v -> 'active', 'durability', v -> 'durability')), '[]') from jsonb_array_elements(st -> 'vehicles') v)),
    'cooldowns', (select coalesce(jsonb_object_agg(h.lot_id, h.e), '{}') from (select lot_id, max(started_at) + make_interval(mins => (cfg -> 'help' ->> 'lot_cooldown_minutes')::int) e
        from public.lot_helps where owner = p_target and started_at > now() - make_interval(mins => (cfg -> 'help' ->> 'lot_cooldown_minutes')::int) group by lot_id) h),
    'limits', jsonb_build_object(
      'given', (select count(*) from public.lot_helps where helper = p_viewer and given_day = dv),
      'given_max', (cfg -> 'help' ->> 'given_per_day')::int,
      'received', (select count(*) from public.lot_helps where owner = p_target and received_day = dt),
      'received_max', (cfg -> 'help' ->> 'received_per_day')::int,
      'liked', exists (select 1 from public.farm_likes where liker = p_viewer and target = p_target and day = dv),
      'noted', (select count(*) from public.visit_notes where from_user = p_viewer and to_user = p_target and day = dv) >= (cfg -> 'notes' ->> 'per_target_per_day')::int,
      'notes_today', (select count(*) from public.visit_notes where from_user = p_viewer and day = dv),
      'help_xp', round(((public.prod_ref(p_viewer) ->> 'xp_h')::numeric * (cfg -> 'help' ->> 'xp_minutes_of_production')::numeric / 60), 2)));
end;
$$;
