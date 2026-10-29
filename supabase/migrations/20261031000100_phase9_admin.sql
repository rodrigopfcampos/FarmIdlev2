-- Fase 9: painel completo e antitrapaça. Papéis (Leitor, Moderador, Admin), situação da conta (advertida, suspensa, banida),
-- alertas com nota de risco e aviso no Discord (pg_net + segredo no Vault), regras automáticas da GDD seção 12,
-- guias do painel (visão geral, economia, progresso, expedições, cartas, missões, denúncias, balanceamento e auditoria).
-- Números em config/anticheat.json. Nunca bane sozinho.

-- envio para o Discord: extensão gratuita do Supabase (no banco local de testes ela não existe e o envio fica desligado)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end $$;

-- ---------- conta e papéis ----------
alter table public.profiles add column admin_role text check (admin_role in ('reader', 'moderator', 'admin'));
update public.profiles set admin_role = 'admin' where is_admin;
alter table public.profiles add column account_status text not null default 'active' check (account_status in ('active', 'warned', 'suspended', 'banned'));
alter table public.profiles add column status_until timestamptz;           -- fim da suspensão
alter table public.profiles add column status_reason text;                 -- o que o jogador vê
alter table public.profiles add column warning_seen boolean not null default true;
alter table public.profiles add column market_frozen boolean not null default false;  -- para o mercado (8c)
alter table public.profiles add column tz_mismatch_since timestamptz;      -- fuso do aparelho diferente da conta desde

-- ---------- tabelas ----------
create table public.alerts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete restrict,
  rule text not null,
  score integer not null,
  evidence jsonb not null default '{}',
  status text not null default 'open' check (status in ('open', 'archived', 'escalated')),
  risk_after integer not null default 0,                         -- nota de risco da conta logo depois deste alerta
  notified boolean not null default false,
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);
create index alerts_user on public.alerts (user_id, created_at);
create index alerts_status on public.alerts (status, created_at);

create table public.farm_days (                                   -- dias com atividade (retenção e ativos por dia)
  user_id uuid not null references public.profiles (id) on delete restrict,
  day date not null,                                             -- dia UTC
  actions integer not null default 0,
  primary key (user_id, day)
);
create index farm_days_day on public.farm_days (day);

create table public.action_times (                                -- instantes das ações (detecção de robô); guarda poucas horas
  user_id uuid not null references public.profiles (id) on delete restrict,
  at timestamptz not null default clock_timestamp()
);
create index action_times_user on public.action_times (user_id, at);

create table public.refusals (                                    -- ações recusadas que o jogo informou
  user_id uuid not null references public.profiles (id) on delete restrict,
  fn text not null,
  msg text not null,
  at timestamptz not null default now()
);
create index refusals_user on public.refusals (user_id, at);

alter table public.farms add column ac_checked_at timestamptz;       -- última passada do antitrapaça
alter table public.player_reports add column handled_by uuid;
alter table public.player_reports add column handled_at timestamptz;
alter table public.player_reports add column handled_note text;

alter table public.alerts enable row level security;
alter table public.farm_days enable row level security;
alter table public.action_times enable row level security;
alter table public.refusals enable row level security;
revoke all on public.alerts, public.farm_days, public.action_times, public.refusals from anon, authenticated;

-- ---------- guarda do painel ----------
create or replace function public.role_rank(p_role text)
returns int language sql immutable set search_path = '' as $$
  select coalesce(array_position(array['reader', 'moderator', 'admin'], p_role), 0)
$$;

-- papel mínimo para cada ação; sempre com 2FA
create or replace function public.admin_need(p_min text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_role text;
begin
  select case when is_admin then 'admin' else admin_role end into v_role from public.profiles where id = v_user;
  if v_user is null or public.role_rank(v_role) < public.role_rank(p_min) or public.role_rank(v_role) = 0 then
    raise exception 'acesso só para admin' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'admin precisa entrar com 2FA' using errcode = 'insufficient_privilege';
  end if;
  return v_user;
end;
$$;

-- o antigo continua sendo "admin"
create or replace function public.admin_guard()
returns uuid language sql stable security definer set search_path = '' as $$
  select public.admin_need('admin')
$$;

create or replace function public.admin_whoami()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'is_admin', public.role_rank(r) > 0,
    'role', r,
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'))
  from (select (select case when is_admin then 'admin' else admin_role end from public.profiles where id = auth.uid()) r) x
$$;

-- ---------- alertas ----------
create or replace function public.account_risk(p_user uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select least(100, coalesce(sum(score), 0))::int from public.alerts
  where user_id = p_user and status <> 'archived'
    and created_at > now() - make_interval(days => (public.config_get('anticheat') ->> 'risk_window_days')::int)
$$;

-- manda para o Discord (só se a extensão existe e o segredo "discord_alerts_webhook" está no Vault)
create or replace function public.alert_notify(p_alert bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare a public.alerts; v_url text; v_nick text; v_name text;
begin
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null or to_regclass('vault.decrypted_secrets') is null then return false; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1' into v_url using 'discord_alerts_webhook';
  if v_url is null or v_url = '' then return false; end if;
  select * into a from public.alerts where id = p_alert;
  select nickname into v_nick from public.profiles where id = a.user_id;
  v_name := coalesce(public.config_get('anticheat') -> 'rules' -> a.rule ->> 'name_pt', a.rule);
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using v_url,
      jsonb_build_object('username', 'Village Idle Farm', 'content',
        format(E'⚠️ **%s** · %s (nota %s, risco da conta %s)\nJogador: **%s** `%s`\nEvidência: `%s`',
          v_name, case when a.score >= 70 then 'crítico' else 'alerta' end, a.score, a.risk_after, coalesce(v_nick, '?'), a.user_id, left(a.evidence::text, 900))),
      '{"Content-Type": "application/json"}'::jsonb;
  update public.alerts set notified = true where id = p_alert;
  return true;
end;
$$;

-- cria o alerta (um por regra por conta a cada 24 h), soma a nota de risco e avisa no Discord a partir de 70
create or replace function public.raise_alert(p_user uuid, p_rule text, p_evidence jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare c jsonb := public.config_get('anticheat'); v_score int; v_id bigint; v_risk int;
begin
  v_score := coalesce((c -> 'rules' -> p_rule ->> 'score')::int, 0);
  if exists (select 1 from public.alerts where user_id = p_user and rule = p_rule
             and created_at > now() - make_interval(hours => (c ->> 'dedupe_hours')::int)) then return null; end if;
  insert into public.alerts (user_id, rule, score, evidence) values (p_user, p_rule, v_score, coalesce(p_evidence, '{}')) returning id into v_id;
  v_risk := public.account_risk(p_user);
  update public.alerts set risk_after = v_risk where id = v_id;
  if v_risk >= (c ->> 'freeze_market_from')::int then update public.profiles set market_frozen = true where id = p_user; end if;
  if v_score > 0 and v_risk >= (c ->> 'notify_from')::int then perform public.alert_notify(v_id); end if;
  return v_id;
end;
$$;

-- dedicado da simulação: em que dia chega a este nível (interpolação dos pontos da config)
create or replace function public.dedicated_day(p_level int)
returns double precision language sql stable set search_path = '' as $$
  with pts as (select (x ->> 0)::double precision lv, (x ->> 1)::double precision d, row_number() over () i
               from jsonb_array_elements(public.config_get('anticheat') -> 'rules' -> 'progress' -> 'dedicated_level_days') x),
  seg as (select a.lv l0, a.d d0, b.lv l1, b.d d1 from pts a join pts b on b.i = a.i + 1)
  select coalesce((select d0 + (p_level - l0) / nullif(l1 - l0, 0) * (d1 - d0) from seg where p_level between l0 and l1 limit 1), 0)
$$;

-- regras da GDD seção 12 (passa no máximo 1 vez por hora por conta, dentro da própria ação do jogador)
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
  select count(*) into v_cards from public.cards where user_id = p_user and origin <> 'admin';
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

-- ---------- o jogo informa ----------
-- relógio e fuso do aparelho (o servidor nunca usa esse relógio; só registra a diferença)
create or replace function public.client_ping(p_client_ms bigint, p_tz text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_skew double precision; c jsonb := public.config_get('anticheat') -> 'rules';
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  v_skew := abs(extract(epoch from now()) * 1000 - p_client_ms) / 60000;
  if v_skew > (c -> 'clock' ->> 'max_skew_minutes')::double precision then
    perform public.raise_alert(v_user, 'clock', jsonb_build_object('skew_min', round(v_skew::numeric, 1)));
  end if;
  update public.profiles set tz_mismatch_since = case
      when p_tz is null or p_tz = timezone then null
      else coalesce(tz_mismatch_since, now()) end
    where id = v_user;
  return jsonb_build_object('ok', true);
end;
$$;

-- ação recusada pelo servidor (o jogo avisa; serve só para a regra de manipulação)
create or replace function public.log_refusal(p_fn text, p_msg text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;
  if (select count(*) from public.refusals where user_id = v_user and at > now() - interval '1 hour') >= 200 then return; end if;
  insert into public.refusals (user_id, fn, msg) values (v_user, left(coalesce(p_fn, ''), 60), left(coalesce(p_msg, ''), 200));
end;
$$;

-- ---------- situação da conta ----------
create or replace function public.account_block_reason(p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when account_status = 'banned' then 'conta banida'
    when account_status = 'suspended' and (status_until is null or status_until > now()) then 'conta suspensa'
    else null end
  from public.profiles where id = p_user
$$;

-- a cada ação: conta bloqueada não joga; a fazenda anda; atividade do dia; antitrapaça 1 vez por hora; prêmios da Encomenda
create or replace function public.touch_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_block text := public.account_block_reason(p_user);
begin
  if v_block is not null then raise exception '%', v_block using errcode = 'insufficient_privilege'; end if;
  perform public.advance_farm(p_user, now());
  update public.farms set last_activity_at = now() where user_id = p_user;
  insert into public.farm_days (user_id, day, actions) values (p_user, (now() at time zone 'UTC')::date, 1)
    on conflict (user_id, day) do update set actions = public.farm_days.actions + 1;
  -- a sincronização automática do jogo não conta como clique
  if coalesce(current_setting('vif.sync', true), '') <> '1' then
    insert into public.action_times (user_id) values (p_user);
  end if;
  perform public.village_settle(p_user);
  perform public.anticheat_check(p_user);
end;
$$;

create or replace function public.get_farm()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.farms where user_id = v_user) then perform public.create_farm(v_user); end if;
  perform set_config('vif.sync', '1', true);
  perform public.touch_farm(v_user);
  perform set_config('vif.sync', '', true);
  return public.farm_state(v_user);
end;
$$;

-- o estado da fazenda leva também a situação da conta (advertência que o jogador ainda não viu)
create or replace function public.social_badge(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with f as (select social_seen_at s from public.farms where user_id = p_user)
  select jsonb_build_object('social', jsonb_build_object(
    'incoming', (select count(*) from public.friendships x where (x.user_a = p_user or x.user_b = p_user) and x.status = 'pending' and x.requested_by <> p_user),
    'unseen', (select count(*) from public.lot_helps h, f where h.owner = p_user and h.started_at > f.s)
            + (select count(*) from public.visit_notes n, f where n.to_user = p_user and n.created_at > f.s)
            + (select count(*) from public.farm_likes l, f where l.target = p_user and l.created_at > f.s),
    'helps', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', h.lot_id, 'kind', h.kind, 'pct', h.pct, 'ends_at', h.ends_at,
                'from', (select nickname from public.profiles where id = h.helper)) order by h.ends_at), '[]')
              from public.lot_helps h where h.owner = p_user and h.kind = 'growth' and h.ends_at > now()),
    'likes', (select likes_total from public.farms where user_id = p_user)),
    'village', jsonb_build_object('title', public.village_title(p_user), 'stars', (select stars from public.farms where user_id = p_user)),
    'account', (select jsonb_build_object('status', account_status, 'warning', case when not warning_seen then status_reason end)
                from public.profiles where id = p_user))
$$;

create or replace function public.warning_seen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  update public.profiles set warning_seen = true where id = v_user;
  return public.farm_state(v_user);
end;
$$;

-- ---------- ações do painel ----------
-- advertir, suspender (dias), banir (só admin) ou reativar; sempre com justificativa e registro
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

-- reverter um lançamento: lança o valor contrário (o ledger nunca é apagado)
create or replace function public.admin_revert_ledger(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); l public.ledger;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select * into l from public.ledger where id = p_id;
  if not found then raise exception 'lançamento não encontrado' using errcode = 'check_violation'; end if;
  if l.reason = 'admin_revert' then raise exception 'não dá para reverter uma reversão' using errcode = 'check_violation'; end if;
  perform public.ledger_post(l.user_id, -l.amount, 'admin_revert', jsonb_build_object('reverts', l.id, 'admin', v_admin, 'reason', p_reason), 'revert:' || l.id);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.revert_ledger', l.user_id, jsonb_build_object('ledger', l.id, 'amount', l.amount, 'reason', p_reason));
  return public.admin_player_summary(l.user_id);
end;
$$;

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

-- ficha do jogador para a guia Jogadores: situação, papel, risco, alertas, logins por dia, cartas e itens
create or replace function public.admin_player_summary(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select jsonb_build_object(
    'id', p.id, 'nickname', p.nickname, 'created_at', p.created_at, 'timezone', p.timezone,
    'status', p.account_status, 'status_until', p.status_until, 'status_reason', p.status_reason,
    'role', case when p.is_admin then 'admin' else p.admin_role end, 'market_frozen', p.market_frozen,
    'risk', public.account_risk(p.id),
    'alerts', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'rule', a.rule, 'score', a.score, 'status', a.status, 'at', a.created_at, 'evidence', a.evidence) order by a.id desc), '[]')
               from (select * from public.alerts where user_id = p.id order by id desc limit 30) a),
    'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'actions', d.actions) order by d.day desc), '[]')
             from (select * from public.farm_days where user_id = p.id order by day desc limit 30) d),
    'cards', (select coalesce(jsonb_object_agg(r, n), '{}') from (select rarity r, count(*) n from public.cards where user_id = p.id group by rarity) x),
    'cards_by_origin', (select coalesce(jsonb_object_agg(o, n), '{}') from (select origin o, count(*) n from public.cards where user_id = p.id group by origin) x),
    'armory', (select count(*) from public.armory where user_id = p.id),
    'stars', (select stars from public.farms where user_id = p.id),
    'friends', (select count(*) from public.friendships where (user_a = p.id or user_b = p.id) and status = 'accepted'),
    'reports_against', (select count(*) from public.player_reports where target = p.id))
    from public.profiles p where p.id = p_user);
end;
$$;

-- ---------- fila de alertas e denúncias ----------
create or replace function public.admin_alerts(p_status text default 'open', p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(x order by (x ->> 'risk')::int desc, (x ->> 'id')::bigint desc), '[]') from (
    select jsonb_build_object('id', a.id, 'user_id', a.user_id, 'nickname', p.nickname, 'rule', a.rule, 'score', a.score, 'risk', public.account_risk(a.user_id),
      'status', a.status, 'evidence', a.evidence, 'at', a.created_at, 'notified', a.notified, 'note', a.review_note) x
    from public.alerts a join public.profiles p on p.id = a.user_id
    where p_status = 'all' or a.status = p_status
    order by a.id desc limit least(greatest(p_limit, 1), 500)) y);
end;
$$;

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

-- rodar o antitrapaça agora em todas as contas ativas (ou numa só)
create or replace function public.admin_run_anticheat(p_user uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('moderator'); u uuid; n int := 0; k int := 0;
begin
  for u in select user_id from public.farms where (p_user is null and last_activity_at > now() - interval '30 days') or user_id = p_user loop
    n := n + public.anticheat_check(u, true); k := k + 1;
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_admin, 'admin.run_anticheat', p_user, jsonb_build_object('accounts', k, 'alerts', n));
  return jsonb_build_object('accounts', k, 'alerts', n);
end;
$$;

-- alerta de teste (confere o Discord)
create or replace function public.admin_test_alert()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); v_id bigint; v_sent boolean;
begin
  insert into public.alerts (user_id, rule, score, evidence, status, risk_after)
    values (v_admin, 'test', 0, jsonb_build_object('teste', 'alerta de teste do painel'), 'archived', 0) returning id into v_id;
  v_sent := public.alert_notify(v_id);
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.test_alert', jsonb_build_object('alert', v_id, 'sent', v_sent));
  return jsonb_build_object('alert', v_id, 'sent', v_sent);
end;
$$;

create or replace function public.admin_reports(p_status text default 'open')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'reporter', pr.nickname, 'target', r.target, 'target_nick', pt.nickname, 'reason', r.reason,
      'status', r.status, 'at', r.created_at, 'note', r.handled_note, 'against', (select count(*) from public.player_reports x where x.target = r.target)) order by r.id desc), '[]')
    from public.player_reports r join public.profiles pr on pr.id = r.reporter join public.profiles pt on pt.id = r.target
    where p_status = 'all' or r.status = p_status);
end;
$$;

create or replace function public.admin_report_close(p_id bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('moderator');
begin
  update public.player_reports set status = 'closed', handled_by = v_admin, handled_at = now(), handled_note = left(p_note, 300) where id = p_id;
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.report_close', jsonb_build_object('report', p_id, 'note', p_note));
  return public.admin_reports('open');
end;
$$;

-- ---------- guias de leitura ----------
-- visão geral: online agora, ativos, novos, retenção D1/D7/D30, ouro criado e destruído hoje, alertas abertos
create or replace function public.admin_overview()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader'); d date := (now() at time zone 'UTC')::date; ign text[];
begin
  ign := array(select jsonb_array_elements_text(public.config_get('anticheat') -> 'rules' -> 'income' -> 'ignore_reasons'));
  return jsonb_build_object(
    'online', (select count(*) from public.farms where last_activity_at > now() - interval '5 minutes'),
    'dau', (select count(*) from public.farm_days where day = d),
    'wau', (select count(distinct user_id) from public.farm_days where day > d - 7),
    'mau', (select count(distinct user_id) from public.farm_days where day > d - 30),
    'players', (select count(*) from public.farms),
    'new_today', (select count(*) from public.profiles where created_at >= d),
    'new_7d', (select count(*) from public.profiles where created_at >= d - 6),
    'retention', (select jsonb_object_agg('D' || k, (select case when count(*) = 0 then null else round(avg(case when exists (
          select 1 from public.farm_days fd where fd.user_id = p.id and fd.day = (p.created_at at time zone 'UTC')::date + k) then 1 else 0 end)::numeric, 3) end
        from public.profiles p where (p.created_at at time zone 'UTC')::date between d - k - 30 and d - k))
      from unnest(array[1, 7, 30]) k),
    'gold_created_today', (select coalesce(sum(amount), 0) from public.ledger where amount > 0 and created_at >= d and not (reason = any (ign))),
    'gold_destroyed_today', (select coalesce(-sum(amount), 0) from public.ledger where amount < 0 and created_at >= d),
    'gold_circulating', (select coalesce(sum(gold), 0) from public.wallets),
    'alerts_open', (select count(*) from public.alerts where status = 'open' and score > 0),
    'alerts_review', (select count(distinct user_id) from public.alerts where status = 'open' and risk_after >= (public.config_get('anticheat') ->> 'review_from')::int),
    'reports_open', (select count(*) from public.player_reports where status = 'open'));
end;
$$;

-- economia: fontes e drenos por dia e por motivo (últimos dias)
create or replace function public.admin_economy(p_days int default 14)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return jsonb_build_object(
    'by_reason', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'reason', reason, 'in', gin, 'out', gout) order by day desc, reason), '[]') from (
      select (created_at at time zone 'UTC')::date as day, reason, sum(greatest(amount, 0)) as gin, -sum(least(amount, 0)) as gout
      from public.ledger where created_at > now() - make_interval(days => least(greatest(p_days, 1), 90)) group by 1, 2) x),
    'circulating', (select coalesce(sum(gold), 0) from public.wallets),
    'income_by_level', (select coalesce(jsonb_agg(jsonb_build_object('level', level, 'players', n, 'p50', p50, 'p90', p90, 'R', public.ref_income(level)) order by level), '[]') from (
      select f.level, count(*) n, percentile_cont(0.5) within group (order by g.v) p50, percentile_cont(0.9) within group (order by g.v) p90
      from public.farms f join lateral (select coalesce(sum(amount), 0) v from public.ledger l where l.user_id = f.user_id and l.amount > 0
        and l.created_at > now() - interval '24 hours' and l.reason not in ('test_grant', 'admin_grant')) g on true
      group by f.level) y));
end;
$$;

-- progresso: nível × idade da conta, com o dia em que o dedicado chega a esse nível
create or replace function public.admin_progress()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'level', f.level,
      'lots', (select count(*) from public.owned_lots l where l.user_id = p.id),
      'age_days', round((extract(epoch from (now() - p.created_at)) / 86400)::numeric, 1),
      'dedicated_day', round(public.dedicated_day(f.level)::numeric, 1),
      'fast', f.level >= 6 and extract(epoch from (now() - p.created_at)) / 86400 < public.dedicated_day(f.level) * 0.9) order by f.level desc), '[]')
    from public.profiles p join public.farms f on f.user_id = p.id);
end;
$$;

-- expedições: sucesso real × teórico por rota e veículo
create or replace function public.admin_expeditions()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('route', route_id, 'vehicle', vehicle_id, 'trips', n, 'expected', exp, 'real', real, 'crit', crit) order by route_id, vehicle_id), '[]') from (
    select route_id, vehicle_id, count(*) n, round(avg(chance)::numeric, 3) exp,
      round(avg(case when outcome <> 'fail' then 1 else 0 end)::numeric, 3) real, round(avg(case when outcome = 'crit' then 1 else 0 end)::numeric, 3) crit
    from public.expeditions where status = 'back' group by 1, 2) x);
end;
$$;

-- cartas: tiradas por raridade × chance da tabela, por origem
create or replace function public.admin_cards()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return jsonb_build_object(
    'by_rarity', (select coalesce(jsonb_agg(jsonb_build_object('rarity', rarity, 'n', n, 'share', round(n::numeric / nullif(t, 0), 4),
        'expected', (public.config_get('cards') -> 'gacha' -> 'effective_rates_with_pity' ->> rarity)::numeric)), '[]')
      from (select rarity, count(*) n, sum(count(*)) over () t from public.cards where origin not in ('admin') group by rarity) x),
    'by_origin', (select coalesce(jsonb_object_agg(origin, n), '{}') from (select origin, count(*) n from public.cards group by origin) y),
    'armory_complete', (select count(*) from (select user_id, card_id from public.armory group by 1, 2 having count(*) = 5) z),
    'sold_to_collector', (select count(*) from public.cards where state = 'sold'));
end;
$$;

-- missões: quantas vezes saiu, quantas foram completadas e o tempo médio
create or replace function public.admin_missions()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', mission_id, 'kind', kind, 'drawn', n, 'done', d, 'rate', round(d::numeric / n, 3), 'avg_hours', h) order by kind, mission_id), '[]') from (
    select mission_id, kind, count(*) n, count(done_at) d,
      round((avg(extract(epoch from (done_at - period::timestamptz)) / 3600) filter (where done_at is not null))::numeric, 1) h
    from public.missions group by 1, 2) x);
end;
$$;

-- balanceamento: versões de cada config e voltar uma versão (cria uma versão nova igual à antiga)
create or replace function public.admin_config_versions(p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'version', version, 'md5', md5(data::text), 'source', data ->> 'source', 'created_at', created_at) order by name, version desc), '[]')
    from public.game_config where p_name is null or name = p_name);
end;
$$;

create or replace function public.admin_config_restore(p_name text, p_version int, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('admin'); v_new int; v_data jsonb;
begin
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select data into v_data from public.game_config where name = p_name and version = p_version;
  if v_data is null then raise exception 'versão não encontrada' using errcode = 'check_violation'; end if;
  select max(version) + 1 into v_new from public.game_config where name = p_name;
  insert into public.game_config (name, version, data) values (p_name, v_new, v_data || jsonb_build_object('version', v_new, 'restored_from', p_version));
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.config_restore', jsonb_build_object('name', p_name, 'from', p_version, 'to', v_new, 'reason', p_reason));
  return public.admin_config_versions(p_name);
end;
$$;

-- auditoria: tudo o que os admins fizeram
create or replace function public.admin_audit_admins(p_limit int default 200)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'at', a.created_at, 'admin', p.nickname, 'action', a.action, 'target', a.target_user_id, 'data', a.data) order by a.id desc), '[]')
    from (select * from public.audit_log where action like 'admin.%' order by id desc limit least(greatest(p_limit, 1), 1000)) a
    left join public.profiles p on p.id = a.actor_id);
end;
$$;

-- as consultas antigas do painel passam a aceitar Leitor e Moderador
create or replace function public.admin_search_players(p_query text)
returns table (user_id uuid, nickname text, email text, gold numeric, created_at timestamptz, last_activity_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.search', jsonb_build_object('query', left(p_query, 100)));
  return query
    select p.id, p.nickname, u.email::text, w.gold, p.created_at, f.last_activity_at
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.wallets w on w.user_id = p.id
    left join public.farms f on f.user_id = p.id
    where coalesce(p_query, '') = '' or p.nickname ilike '%' || p_query || '%' or u.email ilike '%' || p_query || '%' or p.id::text = p_query
    order by p.created_at desc
    limit 50;
end;
$$;

create or replace function public.admin_player_ledger(p_user uuid, p_limit int default 100)
returns setof public.ledger
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_ledger', p_user);
  return query select * from public.ledger where user_id = p_user order by id desc limit least(greatest(p_limit, 1), 500);
end;
$$;

create or replace function public.admin_player_audit(p_user uuid, p_limit int default 100)
returns setof public.audit_log
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_audit', p_user);
  return query select * from public.audit_log where target_user_id = p_user or actor_id = p_user order by id desc limit least(greatest(p_limit, 1), 500);
end;
$$;

create or replace function public.admin_player_farm(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_need('reader');
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_farm', p_user);
  return public.farm_state(p_user);
end;
$$;

create or replace function public.admin_player_reports(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'reporter', p.nickname, 'reason', r.reason, 'at', r.created_at, 'status', r.status) order by r.created_at desc), '[]')
    from public.player_reports r join public.profiles p on p.id = r.reporter where r.target = p_user);
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array['public.account_risk(uuid)', 'public.alert_notify(bigint)', 'public.raise_alert(uuid, text, jsonb)', 'public.dedicated_day(int)',
    'public.anticheat_check(uuid, boolean)', 'public.account_block_reason(uuid)', 'public.role_rank(text)', 'public.admin_need(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array['public.client_ping(bigint, text)', 'public.log_refusal(text, text)', 'public.warning_seen()',
    'public.admin_set_status(uuid, text, int, text, text)', 'public.admin_revert_ledger(bigint, text)', 'public.admin_set_role(uuid, text, text)',
    'public.admin_player_summary(uuid)', 'public.admin_alerts(text, int)', 'public.admin_alert_set(bigint, text, text)', 'public.admin_run_anticheat(uuid)',
    'public.admin_test_alert()', 'public.admin_reports(text)', 'public.admin_report_close(bigint, text)', 'public.admin_overview()', 'public.admin_economy(int)',
    'public.admin_progress()', 'public.admin_expeditions()', 'public.admin_cards()', 'public.admin_missions()', 'public.admin_config_versions(text)',
    'public.admin_config_restore(text, int, text)', 'public.admin_audit_admins(int)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
