-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.role_rank(p_role text)
returns int language sql immutable set search_path = '' as $$
  select coalesce(array_position(array['reader', 'moderator', 'admin'], p_role), 0)
$$;
