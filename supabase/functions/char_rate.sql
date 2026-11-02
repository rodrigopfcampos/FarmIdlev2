-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
CREATE OR REPLACE FUNCTION public.char_rate(c characters, p_material text, p_durability double precision, fx jsonb)
 RETURNS double precision
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (select public.config_get('characters') ch, public.config_get('tools_and_items') -> 'tool_durability_rules' dr)
  select (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision
       * (public.material_def(p_material) ->> 'work_capacity_multiplier')::double precision * (1 + (fx ->> 'tool_effect')::double precision)
       * case when p_durability < (dr ->> 'low_durability_threshold')::double precision then (dr ->> 'low_durability_capacity_penalty_multiplier')::double precision else 1 end
       * coalesce((ch -> 'role_efficiency' ->> (public.class_def(c.class_id) ->> 'role'))::double precision, (ch -> 'role_efficiency' ->> 'other')::double precision)
       * (1 + public.skill_effect(c.class_id, c.skills, 'work_capacity_pct') / 100 + (fx ->> 'team_capacity')::double precision)
       * case when c.debt > 0 then (ch -> 'salary' ->> 'unpaid_efficiency')::double precision else 1 end
  from cfg
$function$;
