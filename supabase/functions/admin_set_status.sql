-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_set_status(p_user uuid, p_status text, p_days int, p_text text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid; c jsonb := public.config_get('anticheat') -> 'actions';
begin
  v_admin := public.admin_need(case when p_status = 'banned' or (p_status = 'active' and (select account_status from public.profiles where id = p_user) = 'banned') then 'admin' else 'moderator' end);
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if p_status not in ('active', 'warned', 'suspended', 'banned') then raise exception 'situação inválida' using errcode = 'check_violation'; end if;
  if p_user = v_admin then raise exception 'não pode mudar a própria conta' using errcode = 'check_violation'; end if;
  if p_status = 'suspended' and (p_days is null or p_days < 1 or p_days > (c ->> 'suspend_max_days')::int) then
    raise exception 'dias inválidos' using errcode = 'check_violation';
  end if;
  update public.profiles set account_status = p_status,
      status_until = case when p_status = 'suspended' then now() + make_interval(days => p_days) end,
      status_reason = case when p_status = 'active' then null else left(coalesce(nullif(trim(p_text), ''), p_reason), (c ->> 'warn_text_max')::int) end,
      warning_seen = p_status <> 'warned'
    where id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.set_status', p_user, jsonb_build_object('status', p_status, 'days', p_days, 'text', p_text, 'reason', p_reason));
  return public.admin_player_summary(p_user);
end;
$$;
