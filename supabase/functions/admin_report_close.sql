-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_report_close(p_id bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('moderator');
begin
  update public.player_reports set status = 'closed', handled_by = v_admin, handled_at = now(), handled_note = left(p_note, 300) where id = p_id;
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.report_close', jsonb_build_object('report', p_id, 'note', p_note));
  return public.admin_reports('open');
end;
$$;
