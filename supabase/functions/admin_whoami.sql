-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_whoami()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'is_admin', public.role_rank(r) > 0,
    'role', r,
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'))
  from (select (select case when is_admin then 'admin' else admin_role end from public.profiles where id = auth.uid()) r) x
$$;
