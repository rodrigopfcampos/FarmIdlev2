-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_set_role(p_user uuid, p_role text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin');
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if p_role is not null and p_role not in ('reader', 'moderator', 'admin') then raise exception 'papel inválido' using errcode = 'check_violation'; end if;
  if p_user = v_admin then raise exception 'não pode mudar a própria conta' using errcode = 'check_violation'; end if;
  update public.profiles set admin_role = p_role, is_admin = (p_role = 'admin') where id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.set_role', p_user, jsonb_build_object('role', p_role, 'reason', p_reason));
  return public.admin_player_summary(p_user);
end;
$$;
