-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.admin_finish_expeditions(p_user uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_time double precision; n int; m int;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  select farm_time into v_time from public.farms where user_id = p_user;
  update public.expeditions set returns_at = v_time where user_id = p_user and status = 'travel' and returns_at > v_time;
  get diagnostics n = row_count;
  update public.vehicles set refurb_until = v_time where user_id = p_user and refurb_until > v_time;
  get diagnostics m = row_count;
  if n + m = 0 then raise exception 'nenhuma viagem ou reforma em andamento' using errcode = 'check_violation'; end if;
  perform public.process_expeditions(p_user, v_time);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.finish_expeditions', p_user, jsonb_build_object('trips', n, 'refurbs', m, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
