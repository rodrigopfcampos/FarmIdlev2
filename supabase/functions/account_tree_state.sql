-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.account_tree_state(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('skills', f.account_skills, 'points', public.account_points(p_user),
    'spent', public.account_spent(p_user),
    'free_reset', f.account_reset_week is distinct from to_char(public.game_day(now()), 'IYYY-IW'),
    'reset_cost', round(public.ref_income(f.level) * (public.config_get('characters') -> 'account_tree' ->> 'extra_reset_cost_R_ratio')::numeric, 2))
  from public.farms f where f.user_id = p_user
$$;
