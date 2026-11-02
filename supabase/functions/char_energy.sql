-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.char_energy(c characters, fx jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (select public.config_get('characters') ch)
  select jsonb_build_object(
    'max', (ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + coalesce((fx ->> 'acct_max_energy')::double precision, 0),
    'use', (ch -> 'energy' ->> 'use_per_work_hour')::double precision
           * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'absolute')::double precision, 100) / 100,
             (1 - coalesce((fx ->> 'card_use_cut')::double precision, 0)) * greatest(1 - coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_cost_reduction_pct' ->> 'permanent')::double precision, 40) / 100,
                      (1 + (public.skill_effect(c.class_id, c.skills, 'energy_use_pct') + coalesce((fx ->> 'acct_energy_use')::double precision, 0)) / 100)
                           * (1 - (fx ->> 'gerente_cut')::double precision)
                           * case when c.energy < (ch -> 'energy' ->> 'low_energy_fraction')::double precision * ((ch -> 'energy' ->> 'max')::double precision + public.skill_effect(c.class_id, c.skills, 'max_energy') + coalesce((fx ->> 'acct_max_energy')::double precision, 0))
                                  then 1 + coalesce((fx ->> 'low_energy_use')::double precision, 0) else 1 end
                           )),
    'rest', (ch -> 'energy' ->> 'recover_per_rest_hour')::double precision
           * least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'absolute')::double precision, 200) / 100,
             coalesce((fx ->> 'card_rest_buff')::double precision, 0) + least(1 + coalesce((public.config_get('cards') -> 'bonus_caps' -> 'energy_recovery_boost_pct' ->> 'permanent')::double precision, 100) / 100,
                   (1 + (fx ->> 'gato_rest')::double precision) * (1 + (public.skill_effect(c.class_id, c.skills, 'rest_speed_pct') + coalesce((fx ->> 'acct_rest')::double precision, 0)) / 100) * (1 + coalesce((fx ->> 'card_rest_perm')::double precision, 0)))))
  from cfg
$function$;
