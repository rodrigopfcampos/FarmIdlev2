-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.prod_ref(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('missions') -> 'production_reference' pr), f as (select * from public.farms where user_id = p_user)
  select jsonb_build_object(
    'value_h', greatest(coalesce(f.prod_value_h, public.ref_income(f.level) * (pr ->> 'initial_value_R_ratio_per_hour')::numeric),
                        public.ref_income(f.level) / 24 * (pr ->> 'floor_R_ratio')::numeric),
    'xp_h', greatest(coalesce(f.prod_xp_h, 0),
                     coalesce((public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric, 0) * (pr ->> 'initial_xp_per_hour_of_xp_to_next')::numeric
                       * case when f.prod_xp_h is null then 1 else (pr ->> 'floor_R_ratio')::numeric end))
  from f, c
$$;
