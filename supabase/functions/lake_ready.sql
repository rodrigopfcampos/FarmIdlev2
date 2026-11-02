-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.lake_ready(p_user uuid, p_t double precision)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from public.owned_lots ol
                 join lateral (select x from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = ol.lot_id) d on true
                 where ol.user_id = p_user and d.x ->> 'type' = 'pasto_lago' and ol.ready_at <= p_t)
$$;
