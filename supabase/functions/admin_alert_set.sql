-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_alert_set(p_id bigint, p_status text, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('moderator');
begin
  if p_status not in ('open', 'archived', 'escalated') then raise exception 'situação inválida' using errcode = 'check_violation'; end if;
  update public.alerts set status = p_status, reviewed_by = v_admin, reviewed_at = now(), review_note = left(p_note, 300) where id = p_id;
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.alert_set', jsonb_build_object('alert', p_id, 'status', p_status, 'note', p_note));
  return public.admin_alerts('open', 100);
end;
$$;
