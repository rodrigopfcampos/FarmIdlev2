-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_order_current()
returns public.village_orders language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('village') -> 'encomenda'; o public.village_orders; v_items text[] := '{}'; t jsonb; v_pick text; n int;
  v_end timestamptz := (date_trunc('week', now() at time zone 'UTC') + interval '7 days') at time zone 'UTC';
begin
  select * into o from public.village_orders where starts_at <= now() and ends_at > now() order by id desc limit 1;
  if found then return o; end if;
  perform pg_advisory_xact_lock(hashtext('village_order'));
  select * into o from public.village_orders where starts_at <= now() and ends_at > now() order by id desc limit 1;
  if found then return o; end if;
  -- 1 pedido de cada faixa de nível (cultivos de lavoura), para todo mundo ter o que doar
  for t in select x from jsonb_array_elements(c -> 'requested_tiers') x loop
    select y ->> 'id' into v_pick from jsonb_array_elements(public.config_get('crops') -> 'crops') y
      where (y ->> 'unlock_level')::int between (t ->> 0)::int and (t ->> 1)::int and (c -> 'requested_kinds') ? (y ->> 'kind')
      order by public.rand01() limit 1;
    if v_pick is not null then v_items := v_items || v_pick; end if;
  end loop;
  select count(*) into n from public.farms where last_activity_at > now() - make_interval(days => (c ->> 'active_days')::int);
  insert into public.village_orders (name_pt, items, goal, active_players, starts_at, ends_at)
    values (c -> 'names_pt' ->> floor(public.rand01() * jsonb_array_length(c -> 'names_pt'))::int, v_items,
            greatest((c ->> 'goal_min_points')::numeric, n * (c ->> 'goal_points_per_active_player')::numeric), n, now(), v_end)
    returning * into o;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'village.order', null, jsonb_build_object('id', o.id, 'items', o.items, 'goal', o.goal, 'players', n));
  return o;
end;
$$;
