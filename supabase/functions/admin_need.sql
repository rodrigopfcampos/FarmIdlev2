-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_need(p_min text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_role text;
begin
  select case when is_admin then 'admin' else admin_role end into v_role from public.profiles where id = v_user;
  if v_user is null or public.role_rank(v_role) < public.role_rank(p_min) or public.role_rank(v_role) = 0 then
    raise exception 'acesso só para admin' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'admin precisa entrar com 2FA' using errcode = 'insufficient_privilege';
  end if;
  return v_user;
end;
$$;
