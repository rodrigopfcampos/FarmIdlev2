-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.get_farm()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.farms where user_id = v_user) then perform public.create_farm(v_user); end if;
  perform set_config('vif.sync', '1', true);
  perform public.touch_farm(v_user);
  perform set_config('vif.sync', '', true);
  return public.farm_state(v_user);
end;
$$;
