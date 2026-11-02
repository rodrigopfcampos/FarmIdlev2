-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.silo_add(p_user uuid, p_items jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.silo (user_id, item_id, qty) select p_user, key, value::int from jsonb_each_text(p_items) where value::int > 0
  on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty
$$;
