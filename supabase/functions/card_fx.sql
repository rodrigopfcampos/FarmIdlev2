-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.card_fx(p_user uuid, p_at timestamptz)
returns jsonb language sql stable security definer set search_path = '' as $$
  with b as (
    select e.key, sum(e.value::double precision) v
    from public.card_buffs cb, jsonb_each_text(public.card_def(cb.card_id) -> 'buff_effects' -> cb.rarity) e
    where cb.user_id = p_user and cb.started_at <= p_at and cb.ends_at > p_at
    group by e.key
  ), lvl as (
    select a.card_id, count(*) n, bool_and(true) filter (where a.rarity in ('common', 'uncommon', 'rare')) part,
           count(*) filter (where a.rarity in ('common', 'uncommon', 'rare')) np
    from public.armory a where a.user_id = p_user group by a.card_id
  ), a as (
    select e.key, sum(e.value::double precision) v
    from lvl, jsonb_each_text(public.card_def(lvl.card_id) -> 'armory_bonus' -> case when lvl.n >= 5 then 'complete_gold' else 'partial_silver' end) e
    where lvl.n >= 5 or lvl.np >= 3
    group by e.key
  )
  select jsonb_build_object('buff', coalesce((select jsonb_object_agg(key, v) from b), '{}'),
                            'armory', coalesce((select jsonb_object_agg(key, v) from a), '{}'))
$$;
