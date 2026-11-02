-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_guard()
returns uuid language sql stable security definer set search_path = '' as $$
  select public.admin_need('admin')
$$;
