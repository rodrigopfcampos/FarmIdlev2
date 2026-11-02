-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.admin_finish_animals(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_time double precision; n int;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  select farm_time into v_time from public.farms where user_id = p_user;
  update public.animals set ready_at = v_time where user_id = p_user and state = 'growing' and ready_at > v_time;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'nenhum animal produzindo' using errcode = 'check_violation'; end if;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.finish_animals', p_user, jsonb_build_object('animals', n, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
