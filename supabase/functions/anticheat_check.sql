-- versão atual (veio de supabase/migrations/20261103000100_v3_card_supply.sql)
create or replace function public.anticheat_check(p_user uuid, p_force boolean default false)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('anticheat'); r jsonb := c -> 'rules'; f public.farms; p public.profiles; n int := 0;
  v_age double precision; v_gain numeric; v_cards int; v_exp numeric; v_succ numeric; v_var numeric; v_cnt int; v_z numeric;
  v_sd double precision; v_acts int; v_ref int;
begin
  select * into f from public.farms where user_id = p_user;
  select * into p from public.profiles where id = p_user;
  if not found or f.user_id is null then return 0; end if;
  if not p_force and f.ac_checked_at is not null and f.ac_checked_at > now() - make_interval(mins => (c ->> 'check_every_minutes')::int) then return 0; end if;
  update public.farms set ac_checked_at = now() where user_id = p_user;
  v_age := extract(epoch from (now() - p.created_at)) / 86400;

  -- renda impossível
  select coalesce(sum(amount), 0) into v_gain from public.ledger
    where user_id = p_user and amount > 0 and created_at > now() - interval '24 hours'
      and not (reason = any (array(select jsonb_array_elements_text(r -> 'income' -> 'ignore_reasons'))));
  if v_gain > public.ref_income(f.level) * (r -> 'income' ->> 'max_R_per_day')::numeric then
    if public.raise_alert(p_user, 'income', jsonb_build_object('gold_24h', v_gain, 'level', f.level, 'R', public.ref_income(f.level))) is not null then n := n + 1; end if;
  end if;

  -- progresso rápido demais
  if f.level >= (r -> 'progress' ->> 'min_level')::int
     and v_age < public.dedicated_day(f.level) * (1 - (r -> 'progress' ->> 'slack')::double precision) then
    if public.raise_alert(p_user, 'progress', jsonb_build_object('level', f.level, 'age_days', round(v_age::numeric, 2),
         'dedicated_day', round(public.dedicated_day(f.level)::numeric, 2))) is not null then n := n + 1; end if;
  end if;

  -- cartas a mais
  select count(*) into v_cards from public.cards where user_id = p_user
    and origin <> all (array(select jsonb_array_elements_text(coalesce(r -> 'cards' -> 'ignore_origins', '["admin"]'))));
  if v_cards > greatest((r -> 'cards' ->> 'min_weeks')::numeric, ceil(v_age / 7)) * (r -> 'cards' ->> 'max_per_week')::numeric then
    if public.raise_alert(p_user, 'cards', jsonb_build_object('cards', v_cards, 'weeks', ceil(v_age / 7))) is not null then n := n + 1; end if;
  end if;

  -- sorte impossível nas expedições (sucessos acima do esperado)
  select count(*), coalesce(sum(case when outcome <> 'fail' then 1 else 0 end), 0), coalesce(sum(chance), 0), coalesce(sum(chance * (1 - chance)), 0)
    into v_cnt, v_succ, v_exp, v_var
    from (select outcome, chance from public.expeditions where user_id = p_user and status = 'back' order by returns_at desc limit (r -> 'luck' ->> 'last_n')::int) x;
  if v_cnt >= (r -> 'luck' ->> 'min_n')::int and v_var > 0 then
    v_z := (v_succ - v_exp) / sqrt(v_var);
    if v_z > (r -> 'luck' ->> 'z')::numeric then
      if public.raise_alert(p_user, 'luck', jsonb_build_object('trips', v_cnt, 'successes', v_succ, 'expected', round(v_exp, 2), 'z', round(v_z, 2))) is not null then n := n + 1; end if;
    end if;
  end if;

  -- robô: intervalos quase iguais entre as ações
  select count(*), stddev_samp(dt) into v_acts, v_sd from (
    select extract(epoch from (at - lag(at) over (order by at))) * 1000 dt from public.action_times
    where user_id = p_user and at > now() - make_interval(mins => (r -> 'robot' ->> 'window_minutes')::int)) x where dt is not null;
  if v_acts >= (r -> 'robot' ->> 'min_actions')::int and v_sd < (r -> 'robot' ->> 'max_stddev_ms')::double precision then
    if public.raise_alert(p_user, 'robot', jsonb_build_object('actions', v_acts, 'stddev_ms', round(v_sd::numeric, 1))) is not null then n := n + 1; end if;
  end if;
  delete from public.action_times where user_id = p_user and at < now() - interval '6 hours';

  -- tentativa de manipular: muitas recusas em 1 hora
  select count(*) into v_ref from public.refusals where user_id = p_user and at > now() - interval '1 hour';
  if v_ref > (r -> 'refusals' ->> 'per_hour')::int then
    if public.raise_alert(p_user, 'refusals', jsonb_build_object('refusals_1h', v_ref,
         'last', (select jsonb_agg(jsonb_build_object('fn', fn, 'msg', msg)) from (select fn, msg from public.refusals where user_id = p_user order by at desc limit 5) z))) is not null then n := n + 1; end if;
  end if;

  -- minigame de robô (o minigame já registra no audit_log)
  if exists (select 1 from public.audit_log where actor_id = p_user and action = 'cheat.minigame_robot' and created_at > now() - interval '24 hours') then
    if public.raise_alert(p_user, 'minigame_robot', jsonb_build_object('count_24h',
         (select count(*) from public.audit_log where actor_id = p_user and action = 'cheat.minigame_robot' and created_at > now() - interval '24 hours'))) is not null then n := n + 1; end if;
  end if;

  -- fuso da conta diferente do aparelho por 7 dias
  if p.tz_mismatch_since is not null and p.tz_mismatch_since < now() - make_interval(days => (r -> 'timezone' ->> 'days')::int) then
    if public.raise_alert(p_user, 'timezone', jsonb_build_object('since', p.tz_mismatch_since, 'account_tz', p.timezone)) is not null then n := n + 1; end if;
  end if;
  return n;
end;
$$;
