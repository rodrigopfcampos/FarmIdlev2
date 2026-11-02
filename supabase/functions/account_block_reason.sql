-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.account_block_reason(p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when account_status = 'banned' then 'conta banida'
    when account_status = 'suspended' and (status_until is null or status_until > now()) then 'conta suspensa'
    else null end
  from public.profiles where id = p_user
$$;
