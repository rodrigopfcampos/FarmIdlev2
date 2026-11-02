-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.admin_grant_stars(p_user uuid, p_amount int, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard();
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  update public.farms set stars = greatest(0, stars + p_amount) where user_id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.grant_stars', p_user, jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;
