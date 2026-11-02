-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.get_village()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  return public.village_state(v_user);
end;
$$;
