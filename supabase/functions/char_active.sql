-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.char_active(c public.characters)
returns boolean
language sql stable
set search_path = ''
as $$
  select c.slot = 'field' and c.leading_id is null and c.unpaid_days < coalesce((public.config_get('characters') -> 'salary' ->> 'stops_after_days')::int, 3)
$$;
