-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.team_rate(p_user uuid, fx jsonb)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'working', coalesce(sum(r) filter (where ch.slot = 'field' and not ch.parked and ch.energy > 0 and public.char_active(ch)), 0),
    'nominal', coalesce(sum(r) filter (where ch.slot = 'field'), 0))
  from public.characters ch
  left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id,
  lateral (select public.char_rate(ch, t.material, coalesce(t.durability, 100), fx) r) x
  where ch.user_id = p_user
$$;
