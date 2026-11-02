-- versão atual (veio de supabase/migrations/20261023000600_phase2_click_play.sql)
create or replace function public.tend_farm(p_target text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is not null and (length(p_target) > 8 or p_target !~ '^[A-Z][0-9]{0,2}(-[0-9]{1,2})?$') then
    raise exception 'canteiro não encontrado' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  perform public.tend_plots(v_user, p_target, true, true);
  return public.farm_state(v_user);
end;
$$;
