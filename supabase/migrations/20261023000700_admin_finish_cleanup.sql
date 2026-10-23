-- Ferramenta de teste do admin: terminar a limpeza dos lotes de um jogador (um lote ou todos),
-- com justificativa e registro na auditoria. Os canteiros do lote ficam livres na hora.
create or replace function public.admin_finish_cleanup(p_user uuid, p_lot text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_time double precision; v_lots jsonb;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.advance_farm(p_user, now()); -- o relógio da fazenda em dia antes de mexer
  select farm_time into v_time from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada' using errcode = 'check_violation'; end if;
  with done as (
    update public.owned_lots set ready_at = v_time
    where user_id = p_user and ready_at > v_time and (p_lot is null or lot_id = p_lot)
    returning lot_id
  )
  select coalesce(jsonb_agg(lot_id), '[]') into v_lots from done;
  if jsonb_array_length(v_lots) = 0 then raise exception 'nenhum lote em limpeza' using errcode = 'check_violation'; end if;
  update public.plots set free_since = v_time
    where user_id = p_user and free_since > v_time and v_lots ? split_part(plot_id, '-', 1);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.finish_cleanup', p_user, jsonb_build_object('lots', v_lots, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

revoke all on function public.admin_finish_cleanup(uuid, text, text) from public, anon;
grant execute on function public.admin_finish_cleanup(uuid, text, text) to authenticated;
