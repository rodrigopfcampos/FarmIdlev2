-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.star_info(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with s as (select public.config_get('village') -> 'stars' st),
  f as (select * from public.farms where user_id = p_user),
  w as (select public.mission_week(public.user_day(p_user, now())) wk)
  select jsonb_build_object(
    'unlocked', f.level >= (s.st ->> 'unlock_level')::int,
    'stars', f.stars,
    'xp', case when f.level >= (s.st ->> 'unlock_level')::int then f.xp else 0 end,
    'per_star', round((public.config_get('levels') -> 'levels' -> 48 ->> 'xp_to_next')::numeric * (s.st ->> 'xp_per_star_ratio_of_level_49')::numeric, 2),
    'packs_week', (select count(*) from public.star_purchases p, w where p.user_id = p_user and p.week = w.wk and p.kind = 'pack'),
    'seeds_week', (select count(*) from public.star_purchases p, w where p.user_id = p_user and p.week = w.wk and p.kind = 'seed'),
    'R', public.ref_income(f.level))
  from f, s
$$;
