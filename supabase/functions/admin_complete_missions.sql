-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.admin_complete_missions(p_user uuid, p_kind text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); m record; d date;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if p_kind not in ('daily', 'weekly') then raise exception 'tipo inválido' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now());
  perform public.mission_ensure(p_user, now());
  d := public.user_day(p_user, now());
  for m in select metric, max(target) t from public.missions
           where user_id = p_user and kind = p_kind and done_at is null and period = case when p_kind = 'daily' then d else public.mission_week(d) end
           group by metric loop
    perform public.mission_progress(p_user, m.metric, m.t);
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.complete_missions', p_user, jsonb_build_object('kind', p_kind, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
