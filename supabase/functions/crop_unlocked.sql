-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.crop_unlocked(p_user uuid, c jsonb, fx jsonb)
returns boolean
language sql stable
set search_path = ''
as $$
  select (c ->> 'unlock_level')::int <= f.level
      or coalesce(fx -> 'early_unlock' ->> 'crop' = c ->> 'id' and (c ->> 'unlock_level')::int <= f.level + (fx -> 'early_unlock' ->> 'levels')::int, false)
  from public.farms f where f.user_id = p_user
$$;
