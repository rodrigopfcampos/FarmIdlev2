-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.mission_target(p_target jsonb, p_ref jsonb, p_animals int)
returns numeric language sql stable set search_path = '' as $$
  select case p_target ->> 'type'
    when 'hours_value' then greatest(1, public.nice_round((p_target ->> 'hours')::numeric * coalesce((p_target ->> 'mult')::numeric, 1) * (p_ref ->> 'value_h')::numeric))
    when 'hours_xp' then greatest(1, public.nice_round((p_target ->> 'hours')::numeric * (p_ref ->> 'xp_h')::numeric))
    when 'animals' then greatest((p_target ->> 'min')::numeric, (p_target ->> 'per_animal')::numeric * p_animals)
    else (p_target ->> 'n')::numeric end
$$;
