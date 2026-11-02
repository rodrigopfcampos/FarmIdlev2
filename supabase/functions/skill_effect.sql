-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.skill_effect(p_class text, p_skills jsonb, p_effect text)
returns double precision
language sql stable
set search_path = ''
as $$
  with cfg as (select public.config_get('characters') c),
  br as (select x, (select (c ->> 'active_phase')::int from cfg) ph, (select (c -> 'skills' ->> 'mastery_points')::int from cfg) mp
         from cfg, jsonb_array_elements(c -> 'skill_tree' -> p_class) x)
  select coalesce(sum(
      case when x -> 'a' ->> 'effect' = p_effect and coalesce((x -> 'a' ->> 'phase')::int, 0) <= ph
           then coalesce((p_skills ->> (x ->> 'id' || '.a'))::double precision, 0) * (x -> 'a' ->> 'per_point')::double precision else 0 end
    + case when x -> 'b' ->> 'effect' = p_effect and coalesce((x -> 'b' ->> 'phase')::int, 0) <= ph
           then coalesce((p_skills ->> (x ->> 'id' || '.b'))::double precision, 0) * (x -> 'b' ->> 'per_point')::double precision else 0 end
    + case when x -> 'mastery' ->> 'effect' = p_effect and coalesce((x -> 'mastery' ->> 'phase')::int, 0) <= ph
                and coalesce((p_skills ->> (x ->> 'id' || '.m'))::int, 0) >= mp
           then (x -> 'mastery' ->> 'value')::double precision else 0 end), 0)
  from br
$$;
