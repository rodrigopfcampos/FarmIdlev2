-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.report_player(p_target uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); cfg jsonb := public.config_get('social'); d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if not exists (select 1 from jsonb_array_elements(cfg -> 'report_reasons') r where r ->> 'id' = p_reason) then raise exception 'motivo inválido' using errcode = 'check_violation'; end if;
  d := public.user_day(v_user, now());
  if (select count(*) from public.player_reports where reporter = v_user and target = p_target and day = d) >= (cfg ->> 'reports_per_target_per_day')::int then
    raise exception 'denúncia já enviada hoje' using errcode = 'check_violation';
  end if;
  insert into public.player_reports (reporter, target, reason, day) values (v_user, p_target, p_reason, d);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'social.report', p_target, jsonb_build_object('reason', p_reason));
  return public.social_state(v_user);
end;
$$;
