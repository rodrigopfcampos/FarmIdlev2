-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.lead_info(p_user uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'available', g.leading_id is null and g.unpaid_days < coalesce((public.config_get('characters') -> 'salary' ->> 'stops_after_days')::int, 3),
    'leading', g.leading_id is not null,
    'vehicles', coalesce((public.config_get('expeditions') -> 'manager' ->> 'vehicles_led')::int, 1) + public.skill_effect('gerente', g.skills, 'lead_two_vehicles')::int,
    'success_pts', (public.config_get('expeditions') -> 'manager' ->> 'success_pts')::double precision
                   + public.skill_effect('gerente', g.skills, 'lead_success_pts'),
    'duration_mult', (public.config_get('expeditions') -> 'manager' ->> 'duration_multiplier')::double precision
                     * (1 + public.skill_effect('gerente', g.skills, 'lead_duration_pct') / 100),
    'capacity_pct', public.skill_effect('gerente', g.skills, 'lead_capacity_pct'),
    'loss_pct', public.skill_effect('gerente', g.skills, 'failure_loss_pct'),
    'insurance_pct', public.skill_effect('gerente', g.skills, 'insurance_cost_pct'),
    'item_pct', public.skill_effect('gerente', g.skills, 'item_chance_pct'),
    'deed_pct', public.skill_effect('gerente', g.skills, 'deed_chance_pct'),
    'crit_pts', public.skill_effect('gerente', g.skills, 'crit_chance_pts'),
    'extra_seconds', (public.config_get('expeditions') -> 'minigame' ->> 'manager_extra_seconds')::double precision)
  from public.characters g where g.user_id = p_user and g.class_id = 'gerente'
$$;
