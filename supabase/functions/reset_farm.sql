-- versão atual (veio de supabase/migrations/20261101000200_v3_reset_keep_farm_row.sql)
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
  -- a linha da fazenda fica (amizades, curtidas e recados apontam para ela): volta tudo ao padrão,
  -- menos as curtidas recebidas e o "visto" das novidades sociais
  execute (select 'update public.farms set ' || string_agg(format('%I = default', column_name), ', ') || ' where user_id = $1'
           from information_schema.columns where table_schema = 'public' and table_name = 'farms'
             and column_name not in ('user_id', 'likes_total', 'social_seen_at', 'created_at'))
    using p_user;
  -- o mesmo começo do create_farm (banco de trabalho inicial e dia do salário)
  update public.farms set
      labor_bank = coalesce((public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision, 0)
                 * coalesce((public.config_get('farm') ->> 'initial_labor_bank_hours')::double precision, 0),
      last_payday = public.game_day(now())
    where user_id = p_user;
  -- ouro de volta ao inicial pelo ledger (lançamento novo, nada é apagado)
  select coalesce(gold, 0) into v_gold from public.wallets where user_id = p_user;
  if coalesce(v_gold, 0) <> v_start then
    perform public.ledger_post(p_user, v_start - coalesce(v_gold, 0), 'farm_reset', jsonb_build_object('reason', p_reason), 'reset:' || p_user || ':' || extract(epoch from clock_timestamp()));
  end if;
  perform public.create_farm(p_user);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (auth.uid(), 'farm.reset', p_user, jsonb_build_object('reason', p_reason, 'gold_before', v_gold));
end;
$$;
