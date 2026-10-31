-- Reformulação v3, parte R1 (mapa novo): o lote A9 virou o Celeiro, o Celeiro passou para o pasto de cima (C1) e o
-- Galinheiro para o de baixo (C2). As regras vêm da config (map_rules v4, lots v7, levels v7).
-- Para recomeçar as contas de teste no mapa novo: zerar a fazenda (o ledger e o audit_log nunca são apagados:
-- o ouro volta ao inicial com um lançamento "farm_reset").

-- zera o progresso de um jogador (só o que é do jogo; amizades, recados, denúncias e histórico ficam)
create or replace function public.reset_farm(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_gold numeric; v_start numeric := coalesce((public.config_get('levels') ->> 'starting_gold')::numeric, 0);
begin
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  delete from public.plots where user_id = p_user;
  delete from public.trees where user_id = p_user;
  delete from public.owned_lots where user_id = p_user;
  delete from public.characters where user_id = p_user;
  delete from public.tools where user_id = p_user;
  delete from public.pets where user_id = p_user;
  delete from public.animals where user_id = p_user;
  delete from public.animal_houses where user_id = p_user;
  delete from public.vehicles where user_id = p_user;
  delete from public.expeditions where user_id = p_user;
  delete from public.minigames where user_id = p_user;
  delete from public.inventory where user_id = p_user;
  delete from public.silo where user_id = p_user;
  delete from public.card_buffs where user_id = p_user;
  delete from public.cards where user_id = p_user;
  delete from public.armory where user_id = p_user;
  delete from public.missions where user_id = p_user;
  delete from public.mission_weeks where user_id = p_user;
  delete from public.star_purchases where user_id = p_user;
  delete from public.village_donations where user_id = p_user;
  delete from public.village_rewards where user_id = p_user;
  delete from public.lot_helps where owner = p_user;
  delete from public.farms where user_id = p_user;
  -- ouro de volta ao inicial pelo ledger (lançamento novo, nada é apagado)
  select coalesce(gold, 0) into v_gold from public.wallets where user_id = p_user;
  if coalesce(v_gold, 0) <> v_start then
    perform public.ledger_post(p_user, v_start - coalesce(v_gold, 0), 'farm_reset', jsonb_build_object('reason', p_reason), 'reset:' || p_user || ':' || extract(epoch from clock_timestamp()));
  end if;
  perform public.create_farm(p_user);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (auth.uid(), 'farm.reset', p_user, jsonb_build_object('reason', p_reason, 'gold_before', v_gold));
end;
$$;
revoke all on function public.reset_farm(uuid, text) from public, anon, authenticated;

-- painel: zerar a fazenda de um jogador (só Admin, com justificativa)
create or replace function public.admin_reset_farm(p_user uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin');
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.reset_farm(p_user, p_reason);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.reset_farm', p_user, jsonb_build_object('reason', p_reason));
  return public.admin_player_summary(p_user);
end;
$$;
revoke all on function public.admin_reset_farm(uuid, text) from public, anon;
grant execute on function public.admin_reset_farm(uuid, text) to authenticated;
