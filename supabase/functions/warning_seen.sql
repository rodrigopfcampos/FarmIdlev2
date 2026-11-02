-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.warning_seen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  update public.profiles set warning_seen = true where id = v_user;
  return public.farm_state(v_user);
end;
$$;
