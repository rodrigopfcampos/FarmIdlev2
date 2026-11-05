-- versão atual (veio de supabase/migrations/20261104000100_v3_hand_use.sql)
create or replace function public.cards_state(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with f as (select * from public.farms where user_id = p_user), d as (select public.user_day(p_user, now()) d)
  select jsonb_build_object(
    'missions', (select coalesce(jsonb_agg(jsonb_build_object('kind', m.kind, 'slot', m.slot, 'id', m.mission_id, 'metric', m.metric,
        'target', m.target, 'progress', m.progress, 'done', m.done_at is not null, 'reward', m.reward) order by m.kind, m.slot), '[]')
      from public.missions m, d where m.user_id = p_user and ((m.kind = 'daily' and m.period = d.d) or (m.kind = 'weekly' and m.period = public.mission_week(d.d)))),
    'mission_week', (select jsonb_build_object('daily_packs', coalesce(w.daily_packs, 0), 'weekly_rewards', coalesce(w.weekly_rewards, 0))
      from d left join public.mission_weeks w on w.user_id = p_user and w.week = public.mission_week(d.d)),
    'reroll_used', (select f.reroll_day is not distinct from d.d from f, d),
    'pack_today', (select f.daily_pack_day is not distinct from d.d from f, d),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'state', c.state,
        'inbox_until', c.inbox_until, 'seen', c.seen, 'origin', c.origin,
        'uses', coalesce(c.uses_left, public.card_full_uses(c.rarity)), 'full_uses', public.card_full_uses(c.rarity), 'repairs', c.repairs) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and c.state in ('binder', 'inbox', 'worn', 'hand')),
    'new_cards', (select coalesce(jsonb_agg(jsonb_build_object('serial', c.serial, 'card_id', c.card_id, 'rarity', c.rarity, 'origin', c.origin) order by c.serial), '[]')
      from public.cards c where c.user_id = p_user and not c.seen),
    'buffs', (select coalesce(jsonb_agg(jsonb_build_object('card_id', b.card_id, 'rarity', b.rarity, 'serial', b.serial, 'started_at', b.started_at, 'ends_at', b.ends_at,
        'locked_until', b.locked_until, 'coin_value', b.coin_value, 'uses', b.uses_left, 'full_uses', public.card_full_uses(b.rarity)) order by b.started_at), '[]') from public.card_buffs b where b.user_id = p_user and b.ends_at > now()),
    'hand_slots', (select public.hand_slots(f.level) from f),
    'repair_cost', public.card_repair_cost(p_user),
    'armory', (select coalesce(jsonb_agg(jsonb_build_object('card_id', a.card_id, 'rarity', a.rarity)), '[]') from public.armory a where a.user_id = p_user),
    'pity', (select jsonb_build_object('rare', f.pity_rare, 'legendary', f.pity_legendary, 'mythic', f.pity_mythic) from f),
    'binder_slots', (select f.binder_slots from f),
    'prod_ref', public.prod_ref(p_user),
    'collector', (select jsonb_object_agg(r, public.collector_price(p_user, r)) from unnest(array['common', 'uncommon', 'rare', 'legendary', 'mythic']) r),
    'binder_expand_cost', (select round(public.ref_income(f.level) * (public.config_get('cards') -> 'binder' ->> 'expansion_cost_reference_income_ratio')::numeric, 2) from f))
$$;
