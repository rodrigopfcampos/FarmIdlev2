-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.house_ready(p_user uuid, p_house text, p_t double precision)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from public.owned_lots ol where ol.user_id = p_user and ol.lot_id = public.house_lot(p_house) and ol.ready_at <= p_t)
$$;
