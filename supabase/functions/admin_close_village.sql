-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.admin_close_village(p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard(); o public.village_orders;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  o := public.village_order_current();
  update public.village_orders set ends_at = now() - interval '1 second' where id = o.id;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.close_village', null, jsonb_build_object('order', o.id, 'reason', p_reason));
  return jsonb_build_object('closed', o.id);
end;
$$;
