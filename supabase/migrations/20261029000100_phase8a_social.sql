-- Fase 8a: amigos, visitas, Ajudar (crescimento ou limpeza), Curtir, recados de emojis pré-definidos, bloqueio e denúncia.
-- Regras na GDD seção 9 (Visitas) e 15 (sem chat livre); números em config/social.json.

-- ---------- tabelas ----------
create table public.friendships (
  user_a uuid not null references public.farms (user_id) on delete restrict,   -- o menor id do par
  user_b uuid not null references public.farms (user_id) on delete restrict,
  requested_by uuid not null,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_b on public.friendships (user_b);

create table public.blocks (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  blocked_id uuid not null references public.farms (user_id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (user_id, blocked_id)
);

create table public.lot_helps (
  id bigint generated always as identity primary key,
  owner uuid not null references public.farms (user_id) on delete restrict,
  helper uuid not null references public.farms (user_id) on delete restrict,
  lot_id text not null,
  kind text not null check (kind in ('growth', 'cleanup')),
  pct numeric(8, 2) not null,                                  -- efeito já com o Ferreiro do dono
  started_at timestamptz not null,
  ends_at timestamptz not null,                                -- crescimento: fim do bônus; limpeza: fim da espera do lote
  given_day date not null,                                     -- dia de quem ajudou (limite de 10 dadas)
  received_day date not null,                                  -- dia do dono (limite de 10 recebidas)
  xp numeric(18, 2) not null default 0
);
create index lot_helps_owner on public.lot_helps (owner, ends_at);
create index lot_helps_helper on public.lot_helps (helper, given_day);

create table public.farm_likes (
  liker uuid not null references public.farms (user_id) on delete restrict,
  target uuid not null references public.farms (user_id) on delete restrict,
  day date not null,
  created_at timestamptz not null default now(),
  primary key (liker, target, day)
);
create index farm_likes_target on public.farm_likes (target, created_at);

create table public.visit_notes (
  id bigint generated always as identity primary key,
  from_user uuid not null references public.farms (user_id) on delete restrict,
  to_user uuid not null references public.farms (user_id) on delete restrict,
  emojis text[] not null,
  day date not null,
  created_at timestamptz not null default now()
);
create index visit_notes_to on public.visit_notes (to_user, created_at);
create index visit_notes_from on public.visit_notes (from_user, day);

create table public.player_reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references public.farms (user_id) on delete restrict,
  target uuid not null references public.farms (user_id) on delete restrict,
  reason text not null,
  day date not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now()
);
create index player_reports_target on public.player_reports (target, status);

alter table public.farms add column likes_total integer not null default 0;
alter table public.farms add column social_seen_at timestamptz not null default now();  -- recados e ajudas depois disso são novos

alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.lot_helps enable row level security;
alter table public.farm_likes enable row level security;
alter table public.visit_notes enable row level security;
alter table public.player_reports enable row level security;
revoke all on public.friendships, public.blocks, public.lot_helps, public.farm_likes, public.visit_notes, public.player_reports from anon, authenticated;

-- ---------- ajudantes ----------
create or replace function public.social_blocked(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.blocks where (user_id = p_a and blocked_id = p_b) or (user_id = p_b and blocked_id = p_a))
$$;

create or replace function public.friend_status(p_me uuid, p_other uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select case when f.status = 'accepted' then 'friend' when f.requested_by = p_me then 'sent' else 'received' end
                   from public.friendships f where f.user_a = least(p_me, p_other) and f.user_b = greatest(p_me, p_other)),
                  case when exists (select 1 from public.blocks where user_id = p_me and blocked_id = p_other) then 'blocked' else 'none' end)
$$;

-- nome e nível para as listas
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'level', f.level, 'likes', f.likes_total)
  from public.profiles p join public.farms f on f.user_id = p.id where p.id = p_user
$$;

-- o que vai no estado da fazenda: pedidos, novidades e as ajudas que estão valendo nos lotes
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
    'likes', (select likes_total from public.farms where user_id = p_user)))
$$;

-- painel Amigos: amigos, pedidos, bloqueados, o que recebeu nos últimos dias e os limites de hoje
create or replace function public.social_state(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('social') cfg),
  d as (select public.user_day(p_user, now()) d),
  fr as (select case when x.user_a = p_user then x.user_b else x.user_a end other, x.status, x.requested_by, x.created_at
         from public.friendships x where x.user_a = p_user or x.user_b = p_user),
  act as (
    select 'help' kind, h.helper who, h.started_at at, jsonb_build_object('lot', h.lot_id, 'help', h.kind, 'pct', h.pct) extra
      from public.lot_helps h, c where h.owner = p_user and h.started_at > now() - make_interval(days => (c.cfg ->> 'activity_days')::int)
    union all
    select 'like', l.liker, l.created_at, '{}'::jsonb from public.farm_likes l, c where l.target = p_user and l.created_at > now() - make_interval(days => (c.cfg ->> 'activity_days')::int)
    union all
    select 'note', n.from_user, n.created_at, jsonb_build_object('emojis', to_jsonb(n.emojis))
      from public.visit_notes n, c where n.to_user = p_user and n.created_at > now() - make_interval(days => (c.cfg -> 'notes' ->> 'keep_days')::int)
  )
  select jsonb_build_object(
    'friends', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'accepted'),
    'incoming', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'pending' and fr.requested_by <> p_user),
    'outgoing', (select coalesce(jsonb_agg(public.player_card(fr.other) order by fr.created_at), '[]') from fr where fr.status = 'pending' and fr.requested_by = p_user),
    'blocked', (select coalesce(jsonb_agg(public.player_card(b.blocked_id) order by b.created_at), '[]') from public.blocks b where b.user_id = p_user),
    'activity', (select coalesce(jsonb_agg(x order by x ->> 'at' desc), '[]') from (
        select jsonb_build_object('kind', a.kind, 'from', public.player_card(a.who), 'at', a.at, 'new', a.at > (select social_seen_at from public.farms where user_id = p_user)) || a.extra x
        from act a, c where not public.social_blocked(p_user, a.who) order by a.at desc limit (select (cfg ->> 'activity_max')::int from c)) y),
    'helps_given', (select count(*) from public.lot_helps h, d where h.helper = p_user and h.given_day = d.d),
    'helps_received', (select count(*) from public.lot_helps h, d where h.owner = p_user and h.received_day = d.d),
    'likes', (select likes_total from public.farms where user_id = p_user))
$$;

-- ---------- amigos, busca, bloqueio e denúncia ----------
create or replace function public.search_players(p_query text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); s jsonb := public.config_get('social') -> 'search'; q text := trim(coalesce(p_query, ''));
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if char_length(q) < (s ->> 'min_chars')::int then raise exception 'digite pelo menos 3 letras' using errcode = 'check_violation'; end if;
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  return (select coalesce(jsonb_agg(public.player_card(x.id) || jsonb_build_object('status', public.friend_status(v_user, x.id))), '[]')
    from (select p.id from public.profiles p join public.farms f on f.user_id = p.id
          where p.id <> v_user and p.nickname ilike q || '%' and not exists (select 1 from public.blocks b where b.user_id = p.id and b.blocked_id = v_user)
          order by lower(p.nickname) = lower(trim(p_query)) desc, p.nickname limit (s ->> 'max_results')::int) x);
end;
$$;

create or replace function public.get_social()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  return public.social_state(v_user);
end;
$$;

create or replace function public.friend_request(p_target uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); cfg jsonb := public.config_get('social') -> 'friends'; x public.friendships;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  select * into x from public.friendships where user_a = least(v_user, p_target) and user_b = greatest(v_user, p_target) for update;
  if found and x.status = 'accepted' then raise exception 'vocês já são amigos' using errcode = 'check_violation'; end if;
  if found and x.requested_by = v_user then raise exception 'pedido já enviado' using errcode = 'check_violation'; end if;
  if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'accepted') >= (cfg ->> 'max_friends')::int then
    raise exception 'limite de amigos' using errcode = 'check_violation';
  end if;
  if found then
    -- os dois pediram: vira amizade
    update public.friendships set status = 'accepted', accepted_at = now() where user_a = x.user_a and user_b = x.user_b;
  else
    if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'pending' and requested_by = v_user) >= (cfg ->> 'max_pending_out')::int then
      raise exception 'muitos pedidos esperando' using errcode = 'check_violation';
    end if;
    insert into public.friendships (user_a, user_b, requested_by) values (least(v_user, p_target), greatest(v_user, p_target), v_user);
  end if;
  return public.social_state(v_user);
end;
$$;

create or replace function public.friend_respond(p_other uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); x public.friendships;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  select * into x from public.friendships where user_a = least(v_user, p_other) and user_b = greatest(v_user, p_other) and status = 'pending' and requested_by = p_other for update;
  if not found then raise exception 'pedido não encontrado' using errcode = 'check_violation'; end if;
  if p_accept then
    if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'accepted') >= (public.config_get('social') -> 'friends' ->> 'max_friends')::int then
      raise exception 'limite de amigos' using errcode = 'check_violation';
    end if;
    update public.friendships set status = 'accepted', accepted_at = now() where user_a = x.user_a and user_b = x.user_b;
  else
    delete from public.friendships where user_a = x.user_a and user_b = x.user_b;
  end if;
  return public.social_state(v_user);
end;
$$;

-- desfaz amizade ou cancela pedido
create or replace function public.friend_remove(p_other uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  delete from public.friendships where user_a = least(v_user, p_other) and user_b = greatest(v_user, p_other);
  return public.social_state(v_user);
end;
$$;

-- bloquear: desfaz a amizade; um não acha, não visita e não manda nada ao outro
create or replace function public.block_player(p_target uuid, p_block boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if p_block then
    insert into public.blocks (user_id, blocked_id) values (v_user, p_target) on conflict do nothing;
    delete from public.friendships where user_a = least(v_user, p_target) and user_b = greatest(v_user, p_target);
  else
    delete from public.blocks where user_id = v_user and blocked_id = p_target;
  end if;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, case when p_block then 'social.block' else 'social.unblock' end, p_target, '{}');
  return public.social_state(v_user);
end;
$$;

create or replace function public.report_player(p_target uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); cfg jsonb := public.config_get('social'); d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if not exists (select 1 from jsonb_array_elements(cfg -> 'report_reasons') r where r ->> 'id' = p_reason) then raise exception 'motivo inválido' using errcode = 'check_violation'; end if;
  d := public.user_day(v_user, now());
  if (select count(*) from public.player_reports where reporter = v_user and target = p_target and day = d) >= (cfg ->> 'reports_per_target_per_day')::int then
    raise exception 'denúncia já enviada hoje' using errcode = 'check_violation';
  end if;
  insert into public.player_reports (reporter, target, reason, day) values (v_user, p_target, p_reason, d);
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, 'social.report', p_target, jsonb_build_object('reason', p_reason));
  return public.social_state(v_user);
end;
$$;

create or replace function public.social_seen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  update public.farms set social_seen_at = now() where user_id = v_user;
  return public.social_state(v_user);
end;
$$;

-- ---------- visita ----------
-- o que o visitante vê: a fazenda do dono no horário e clima dele, sem ouro, Silo, inventário, cartas nem missões
create or replace function public.visit_view(p_viewer uuid, p_target uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  st jsonb := public.farm_state(p_target); cfg jsonb := public.config_get('social'); dv date := public.user_day(p_viewer, now()); dt date := public.user_day(p_target, now());
begin
  return jsonb_build_object(
    'owner', public.player_card(p_target) || jsonb_build_object('status', public.friend_status(p_viewer, p_target)),
    'state', (select jsonb_object_agg(key, value) from jsonb_each(st) where key = any (array['server_now', 'game_day', 'weather', 'farm_time', 'synced_at',
        'last_activity_at', 'offline_cap_hours', 'nickname', 'level', 'lots', 'plots', 'trees', 'animals', 'houses', 'lake', 'pet']))
      || jsonb_build_object('helps', st -> 'social' -> 'helps',
        'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p ->> 'pet_id', 'active', true)), '[]') from jsonb_array_elements(st -> 'pets') p where (p ->> 'active')::boolean),
        'vehicles', (select coalesce(jsonb_agg(jsonb_build_object('vehicle_id', v ->> 'vehicle_id', 'rarity', v ->> 'rarity', 'active', v -> 'active', 'durability', v -> 'durability')), '[]') from jsonb_array_elements(st -> 'vehicles') v)),
    'cooldowns', (select coalesce(jsonb_object_agg(h.lot_id, h.e), '{}') from (select lot_id, max(started_at) + make_interval(mins => (cfg -> 'help' ->> 'lot_cooldown_minutes')::int) e
        from public.lot_helps where owner = p_target and started_at > now() - make_interval(mins => (cfg -> 'help' ->> 'lot_cooldown_minutes')::int) group by lot_id) h),
    'limits', jsonb_build_object(
      'given', (select count(*) from public.lot_helps where helper = p_viewer and given_day = dv),
      'given_max', (cfg -> 'help' ->> 'given_per_day')::int,
      'received', (select count(*) from public.lot_helps where owner = p_target and received_day = dt),
      'received_max', (cfg -> 'help' ->> 'received_per_day')::int,
      'liked', exists (select 1 from public.farm_likes where liker = p_viewer and target = p_target and day = dv),
      'noted', (select count(*) from public.visit_notes where from_user = p_viewer and to_user = p_target and day = dv) >= (cfg -> 'notes' ->> 'per_target_per_day')::int,
      'notes_today', (select count(*) from public.visit_notes where from_user = p_viewer and day = dv),
      'help_xp', round(((public.prod_ref(p_viewer) ->> 'xp_h')::numeric * (cfg -> 'help' ->> 'xp_minutes_of_production')::numeric / 60), 2)));
end;
$$;

-- visitar: um jogador escolhido ou, sem alvo, uma fazenda ativa sorteada
create or replace function public.visit_farm(p_target uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); r jsonb := public.config_get('social') -> 'random_visit'; t uuid := p_target;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if t is null then
    select f.user_id into t from public.farms f
      where f.user_id <> v_user and f.level >= (r ->> 'min_level')::int and f.last_activity_at > now() - make_interval(days => (r ->> 'active_days')::int)
        and not public.social_blocked(v_user, f.user_id)
      order by public.rand01() limit 1;
    if t is null then raise exception 'nenhuma fazenda para visitar agora' using errcode = 'check_violation'; end if;
  end if;
  if t = v_user or not exists (select 1 from public.farms where user_id = t) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, t) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  -- a fazenda do dono anda até agora (sem contar como atividade dele)
  perform public.advance_farm(t, now());
  return public.visit_view(v_user, t);
end;
$$;

-- Ajudar: crescimento (+10% por 1 h no lote) ou limpeza (−10% do que falta); quem ajuda ganha XP de 10 min da própria produção
create or replace function public.help_lot(p_target uuid, p_lot text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); cfg jsonb := public.config_get('social') -> 'help'; dv date; dt date; l public.owned_lots; v_t double precision;
  v_kind text; v_pct numeric; v_ferreiro double precision; v_xp numeric; v_type text; v_ends timestamptz;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  perform public.advance_farm(p_target, now());
  dv := public.user_day(v_user, now()); dt := public.user_day(p_target, now());
  -- trava a fazenda de quem ajuda (limite diário) e a do dono (limite recebido e um por lote)
  perform 1 from public.farms where user_id in (v_user, p_target) order by user_id for update;
  if (select count(*) from public.lot_helps where helper = v_user and given_day = dv) >= (cfg ->> 'given_per_day')::int then
    raise exception 'ajudas de hoje acabaram' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.lot_helps where owner = p_target and received_day = dt) >= (cfg ->> 'received_per_day')::int then
    raise exception 'essa fazenda já recebeu todas as ajudas de hoje' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.lot_helps where owner = p_target and lot_id = p_lot and started_at > now() - make_interval(mins => (cfg ->> 'lot_cooldown_minutes')::int)) then
    raise exception 'esse lote já foi ajudado há pouco' using errcode = 'check_violation';
  end if;
  select * into l from public.owned_lots where user_id = p_target and lot_id = p_lot for update;
  if not found then raise exception 'lote não encontrado' using errcode = 'check_violation'; end if;
  select farm_time into v_t from public.farms where user_id = p_target;
  v_type := public.lot_def(p_lot) ->> 'type';
  if l.ready_at > v_t then
    v_kind := 'cleanup';
  elsif v_type in ('lavoura', 'pomar')
        and (exists (select 1 from public.plots where user_id = p_target and split_part(plot_id, '-', 1) = p_lot and state = 'growing')
             or exists (select 1 from public.trees where user_id = p_target and lot_id = p_lot and fruit_id is not null)) then
    v_kind := 'growth';
  else
    raise exception 'nada para ajudar nesse lote' using errcode = 'check_violation';
  end if;
  -- Ferreiro em campo na fazenda do dono (Obras B): +10% por ponto no efeito
  select coalesce(sum(public.skill_effect(ch.class_id, ch.skills, 'neighbor_help_pct')), 0) into v_ferreiro
    from public.characters ch where ch.user_id = p_target and public.char_active(ch);
  v_pct := round(((case when v_kind = 'growth' then cfg ->> 'growth_pct' else cfg ->> 'cleanup_pct' end)::numeric * (1 + v_ferreiro::numeric / 100)), 2);
  if v_kind = 'cleanup' then
    update public.owned_lots set ready_at = v_t + (ready_at - v_t) * (1 - v_pct::double precision / 100) where user_id = p_target and lot_id = p_lot;
    v_ends := now() + make_interval(mins => (cfg ->> 'lot_cooldown_minutes')::int);
  else
    v_ends := now() + make_interval(mins => (cfg ->> 'growth_minutes')::int);
  end if;
  v_xp := round(((public.prod_ref(v_user) ->> 'xp_h')::numeric * (cfg ->> 'xp_minutes_of_production')::numeric / 60), 2);
  insert into public.lot_helps (owner, helper, lot_id, kind, pct, started_at, ends_at, given_day, received_day, xp)
    values (p_target, v_user, p_lot, v_kind, v_pct, now(), v_ends, dv, dt, v_xp);
  if v_xp > 0 then perform public.add_xp(v_user, v_xp); end if;
  perform public.mission_progress(v_user, 'neighbors_helped', 1);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'social.help', p_target, jsonb_build_object('lot', p_lot, 'kind', v_kind, 'pct', v_pct, 'xp', v_xp));
  return public.visit_view(v_user, p_target);
end;
$$;

create or replace function public.like_farm(p_target uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  d := public.user_day(v_user, now());
  insert into public.farm_likes (liker, target, day) values (v_user, p_target, d) on conflict do nothing;
  if not found then raise exception 'já curtiu hoje' using errcode = 'check_violation'; end if;
  update public.farms set likes_total = likes_total + 1 where user_id = p_target;
  return public.visit_view(v_user, p_target);
end;
$$;

-- recado: só emojis da lista (sem texto livre)
create or replace function public.send_note(p_target uuid, p_emojis text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); n jsonb := public.config_get('social') -> 'notes'; d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  if coalesce(cardinality(p_emojis), 0) < 1 or cardinality(p_emojis) > (n ->> 'max_emojis')::int
     or exists (select 1 from unnest(p_emojis) e where not (n -> 'emojis') ? e) then
    raise exception 'recado inválido' using errcode = 'check_violation';
  end if;
  d := public.user_day(v_user, now());
  perform 1 from public.farms where user_id = v_user for update;
  if (select count(*) from public.visit_notes where from_user = v_user and to_user = p_target and day = d) >= (n ->> 'per_target_per_day')::int then
    raise exception 'já deixou recado hoje' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.visit_notes where from_user = v_user and day = d) >= (n ->> 'per_day')::int then
    raise exception 'recados de hoje acabaram' using errcode = 'check_violation';
  end if;
  insert into public.visit_notes (from_user, to_user, emojis, day) values (v_user, p_target, p_emojis, d);
  return public.visit_view(v_user, p_target);
end;
$$;

-- painel do admin: denúncias abertas contra o jogador
create or replace function public.admin_player_reports(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin uuid := public.admin_guard();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'reporter', p.nickname, 'reason', r.reason, 'at', r.created_at, 'status', r.status) order by r.created_at desc), '[]')
    from public.player_reports r join public.profiles p on p.id = r.reporter where r.target = p_user);
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array['public.social_blocked(uuid, uuid)', 'public.friend_status(uuid, uuid)', 'public.player_card(uuid)', 'public.social_badge(uuid)',
    'public.social_state(uuid)', 'public.visit_view(uuid, uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array['public.search_players(text)', 'public.get_social()', 'public.friend_request(uuid)', 'public.friend_respond(uuid, boolean)',
    'public.friend_remove(uuid)', 'public.block_player(uuid, boolean)', 'public.report_player(uuid, text)', 'public.social_seen()',
    'public.visit_farm(uuid)', 'public.help_lot(uuid, text)', 'public.like_farm(uuid)', 'public.send_note(uuid, text[])', 'public.admin_player_reports(uuid)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;

-- ---------- funções que mudam na fase 8a ----------
create or replace function public.advance_farm(p_user uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.farms;
  v_farm jsonb := public.config_get('farm');
  v_work jsonb := public.config_get('crops') -> 'rules' -> 'work_units';
  v_plant_cost double precision := coalesce((v_work ->> 'plant')::double precision, 0.5);
  v_harvest_cost double precision := coalesce((v_work ->> 'harvest')::double precision, 0.5);
  v_step double precision := coalesce((public.config_get('characters') ->> 'step_minutes')::double precision, 10) * 60;
  v_cap_h double precision := coalesce((v_farm ->> 'labor_bank_cap_hours')::double precision, 1);
  v_end timestamptz;
  t0 double precision; t1 double precision; seg0 double precision; seg1 double precision;
  t_cur double precision; labor double precision; labor0 double precision; used double precision;
  rate double precision; cap double precision; fx jsonb; tr jsonb;
  v_gold numeric; v_seed_spent numeric; v_refund numeric; v_plantings int; v_seed numeric; v_feed numeric; v_f numeric;
  e record; lt double precision; te double precision; v_real timestamptz; v_w jsonb; v_g double precision; v_cut double precision; v_help jsonb;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  labor := f.labor_bank;
  seg0 := t0;
  perform public.weather_ensure(p_user, f.synced_at, p_now);
  perform public.mission_ensure(p_user, p_now);
  -- a troca de fuso marcada vale a partir da meia-noite combinada
  update public.profiles set timezone = tz_pending, tz_pending = null, tz_pending_at = null
    where id = p_user and tz_pending is not null and tz_pending_at <= f.synced_at;

  while seg0 < t1 loop
    -- relógio real do passo: o clima e o evento valem pela hora local do jogador
    v_real := f.synced_at + make_interval(secs => seg0 - t0);
    perform set_config('vif.at', v_real::text, true);
    v_w := public.weather_now(p_user, v_real);
    v_cut := extract(epoch from ((v_w ->> 'next')::timestamptz - v_real));
    -- cartas: buffs que acabaram pagam a Moeda da Sorte; o passo também corta no fim do próximo buff
    perform public.buffs_expire(p_user, v_real);
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.card_buffs where user_id = p_user and ends_at > v_real));
    -- ajuda de vizinho: +10% de crescimento no lote enquanto durar (o passo corta no fim)
    v_cut := least(v_cut, (select extract(epoch from min(ends_at) - v_real) from public.lot_helps where owner = p_user and kind = 'growth' and ends_at > v_real));
    v_help := (select coalesce(jsonb_object_agg(lot_id, g), '{}') from (select lot_id, sum(pct) / 100 g from public.lot_helps
               where owner = p_user and kind = 'growth' and started_at <= v_real and ends_at > v_real group by lot_id) h);
    seg1 := least(t1, seg0 + v_step, seg0 + greatest(1, coalesce(v_cut, v_step)));
    -- evento que valeu para a conta (no máximo 1 a cada 20 h, mesmo trocando de fuso)
    if coalesce((v_w -> 'event' ->> 'active')::boolean, false) then
      update public.farms set last_event_start = (v_w -> 'event' ->> 'start')::timestamptz
        where user_id = p_user and last_event_start is distinct from (v_w -> 'event' ->> 'start')::timestamptz;
      -- missão semanal: produção ativa durante o evento (conta 1 vez por evento)
      if (select event_credit from public.farms where user_id = p_user) is distinct from (v_w -> 'event' ->> 'start')::timestamptz
         and (exists (select 1 from public.plots where user_id = p_user and state = 'growing')
              or exists (select 1 from public.trees where user_id = p_user and fruit_id is not null)
              or exists (select 1 from public.animals where user_id = p_user and state = 'growing')) then
        update public.farms set event_credit = (v_w -> 'event' ->> 'start')::timestamptz where user_id = p_user;
        perform public.mission_progress(p_user, 'night_events', 1);
      end if;
    end if;
    -- salário das meias-noites até o fim deste passo (no relógio real)
    perform public.process_payday(p_user, f.synced_at + make_interval(secs => seg1 - t0));
    fx := public.team_fx(p_user);
    if (fx ->> 'auto_pay')::boolean then perform public.pay_debts(p_user); end if;
    perform public.rotate_team(p_user);
    fx := public.team_fx(p_user);
    tr := public.team_rate(p_user, fx);
    -- Sol forte, Calor Dourado e ajuda de vizinho (só no lote ajudado): quem está crescendo anda mais rápido neste passo
    v_g := coalesce((fx ->> 'w_growth')::double precision, 0);
    if v_g > 0 or v_help <> '{}' then
      update public.plots pl set ready_at = case when (pl.ready_at - seg0) / (1 + x.g) <= seg1 - seg0 then seg0 + (pl.ready_at - seg0) / (1 + x.g)
                                                 else pl.ready_at - (seg1 - seg0) * x.g end
        from (select p2.plot_id, v_g + coalesce((v_help ->> split_part(p2.plot_id, '-', 1))::double precision, 0) g
              from public.plots p2 where p2.user_id = p_user) x
        where pl.user_id = p_user and pl.plot_id = x.plot_id and x.g > 0 and pl.state = 'growing' and pl.ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_growth_orchard')::double precision, 0);
    if v_g > 0 or v_help <> '{}' then
      update public.trees t set ready_at = case when (t.ready_at - seg0) / (1 + x.g) <= seg1 - seg0 then seg0 + (t.ready_at - seg0) / (1 + x.g)
                                                else t.ready_at - (seg1 - seg0) * x.g end
        from (select t2.lot_id, t2.slot, v_g + coalesce((v_help ->> t2.lot_id)::double precision, 0) g
              from public.trees t2 where t2.user_id = p_user) x
        where t.user_id = p_user and t.lot_id = x.lot_id and t.slot = x.slot and x.g > 0 and t.fruit_id is not null and t.ready_at > seg0;
    end if;
    -- Ampulheta e Armory: animais e limpeza de lote andam mais rápido
    v_g := coalesce((fx ->> 'w_speed_animal')::double precision, 0);
    if v_g > 0 then
      update public.animals set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                                else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and state = 'growing' and ready_at > seg0;
    end if;
    v_g := coalesce((fx ->> 'w_speed_cleanup')::double precision, 0);
    if v_g > 0 then
      update public.owned_lots set ready_at = case when (ready_at - seg0) / (1 + v_g) <= seg1 - seg0 then seg0 + (ready_at - seg0) / (1 + v_g)
                                                   else ready_at - (seg1 - seg0) * v_g end
        where user_id = p_user and ready_at > seg0;
    end if;
    rate := (tr ->> 'working')::double precision / 3600.0;
    cap := (tr ->> 'nominal')::double precision * v_cap_h;
    if cap > 0 then labor := least(labor, cap); end if; -- teto do trabalho guardado (ninguém em campo: guarda o que tinha)
    cap := greatest(cap, labor);
    labor0 := labor; used := 0; t_cur := seg0;
    select gold into v_gold from public.wallets where user_id = p_user;
    v_seed_spent := 0; v_refund := 0; v_plantings := 0;
    -- animais com fome voltam a produzir quando há ouro para a ração (sem gastar trabalho)
    v_feed := public.animals_feed_hungry(p_user, seg0, fx, v_gold);

    loop
      i := i + 1;
      exit when i > 20000; -- trava de segurança
      select * into e from (
        select 'harvest'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, v_harvest_cost as cost
          from public.plots pl
          where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= seg1
        union all
        select 'harvest_tree', t.lot_id, t.slot, t.ready_at, v_harvest_cost
          from public.trees t
          where t.user_id = p_user and t.fruit_id is not null and t.ready_at <= seg1
        union all
        select 'collect', a.house_id, a.slot, a.ready_at, v_harvest_cost
          from public.animals a
          where a.user_id = p_user and a.state = 'growing' and a.ready_at <= seg1
        union all
        select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost
          from public.plots pl join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
          where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null
            and greatest(coalesce(pl.free_since, t0), ol.ready_at) <= seg1
      ) q
      order by avail, key, slot
      limit 1;
      exit when not found;

      -- quando a equipe terá o trabalho necessário
      lt := least(cap, labor + rate * (greatest(e.avail, t_cur) - t_cur));
      if lt >= e.cost then te := greatest(e.avail, t_cur);
      elsif rate > 0 then te := greatest(e.avail, t_cur) + (e.cost - lt) / rate;
      else te := seg1 + 1; end if;
      exit when te > seg1; -- a fila é única: se a primeira tarefa não cabe, nenhuma cabe neste passo

      if e.kind = 'plant' then
        v_seed := public.seed_price((select crop_id from public.plots where user_id = p_user and plot_id = e.key), fx);
        if v_gold - v_seed_spent - v_feed < v_seed then
          update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
          continue;
        end if;
        v_seed_spent := v_seed_spent + public.plant_plot(p_user, e.key, (select crop_id from public.plots where user_id = p_user and plot_id = e.key), te, fx);
        v_plantings := v_plantings + 1;
      elsif e.kind = 'harvest' then
        v_refund := v_refund + public.harvest_plot(p_user, e.key, te, fx);
      elsif e.kind = 'collect' then
        perform public.animal_collect(p_user, e.key, e.slot, te, fx, true);
        v_f := public.animal_start(p_user, e.key, e.slot, te, fx, v_gold - v_seed_spent - v_feed);
        v_feed := v_feed + coalesce(v_f, 0);
      else
        perform public.harvest_tree(p_user, e.key, e.slot, te, fx);
      end if;
      -- se precisou esperar, no instante te o trabalho juntado é exatamente o custo: sobra 0
      -- (corrige a fase 2, que descontava a espera duas vezes e deixava o trabalho fora do jogo mais lento)
      labor := case when lt >= e.cost then lt - e.cost else 0 end;
      used := used + e.cost;
      t_cur := te;
    end loop;

    if seg1 > t_cur then labor := least(cap, labor + rate * (seg1 - t_cur)); end if;
    labor := greatest(0, labor);
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds', jsonb_build_object('plantings', v_plantings, 'farm_time', round(seg1::numeric, 1)));
    end if;
    if v_refund > 0 then
      perform public.ledger_post(p_user, round(v_refund, 2), 'seed_refund', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    if v_feed > 0 then
      perform public.ledger_post(p_user, -round(v_feed, 2), 'feed', jsonb_build_object('farm_time', round(seg1::numeric, 1)));
    end if;
    -- energia, nível e desgaste na fração do passo em que a equipe produziu trabalho
    perform public.tick_team(p_user, (seg1 - seg0) / 3600.0,
      case when rate > 0 then least(1, greatest(0, (labor - labor0 + used) / (rate * (seg1 - seg0)))) else 0 end, fx);
    -- missão: 3 personagens trabalhando em campo ao mesmo tempo
    if rate > 0 and (select count(*) from public.characters ch where ch.user_id = p_user and ch.slot = 'field' and not ch.parked
                     and ch.energy > 0 and ch.leading_id is null and public.char_active(ch)) >= 3 then
      perform public.mission_progress(p_user, 'field3_hours', ((seg1 - seg0) / 3600.0)::numeric);
    end if;
    if public.auto_sell(p_user, fx) > 0 then
      update public.plots set stalled_reason = null, free_since = seg1 where user_id = p_user and stalled_reason = 'sem_ouro';
    end if;
    seg0 := seg1;
  end loop;

  perform set_config('vif.at', '', true);
  perform public.buffs_expire(p_user, p_now);
  perform public.cards_maintain(p_user);
  -- dias que viraram com a fazenda parada (mais de 8 h fora) também cobram salário
  perform public.process_payday(p_user, p_now);
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  -- expedições: viagens que voltaram, repetições e reformas
  perform public.process_expeditions(p_user, t1);
end;
$function$;

create or replace function public.farm_state(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  fx jsonb := public.team_fx(p_user);
  tr jsonb := public.team_rate(p_user, fx);
  v_level int; base jsonb; v_chars jsonb; v_snacks jsonb;
begin
  select level into v_level from public.farms where user_id = p_user;
  select coalesce(jsonb_agg(jsonb_build_object(
      'class_id', ch.class_id, 'slot', ch.slot, 'energy', round(ch.energy::numeric, 2), 'parked', ch.parked,
      'level', ch.level, 'work_hours', round(ch.work_hours::numeric, 3), 'skills', ch.skills, 'skill_choice', ch.skill_choice,
      'reset_week', ch.reset_week, 'debt', ch.debt, 'unpaid_days', ch.unpaid_days, 'snack_id', ch.snack_id, 'snack_qty', ch.snack_qty,
      'cloth_id', ch.cloth_id, 'amulet_id', ch.amulet_id, 'material', coalesce(t.material, 'wood'), 'durability', round(coalesce(t.durability, 100)::numeric, 2),
      'rate', round(public.char_rate(ch, t.material, coalesce(t.durability, 100), fx)::numeric, 3),
      'energy_max', (public.char_energy(ch, fx) ->> 'max')::numeric, 'energy_use', round((public.char_energy(ch, fx) ->> 'use')::numeric, 3),
      'energy_rest', round((public.char_energy(ch, fx) ->> 'rest')::numeric, 3), 'active', public.char_active(ch), 'leading', ch.leading_id is not null,
      'salary', public.salary_of(p_user, ch)) order by ch.hired_at), '[]')
    into v_chars
    from public.characters ch left join public.tools t on t.user_id = ch.user_id and t.class_id = ch.class_id
    where ch.user_id = p_user;
  select coalesce(jsonb_object_agg(x ->> 'id', round(public.ref_income(v_level) * (x ->> 'price_R_ratio')::numeric * (1 - (fx ->> 'shop_discount')::numeric), 2)), '{}')
    into v_snacks from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x;
  select jsonb_build_object(
    'server_now', now(),
    'game_day', public.user_day(p_user, now()),
    'weather', public.weather_view(p_user, fx),
    'farm_time', f.farm_time,
    'synced_at', f.synced_at,
    'last_activity_at', f.last_activity_at,
    'offline_cap_hours', (public.config_get('farm') ->> 'offline_cap_hours')::int,
    'labor_bank', f.labor_bank,
    'labor_per_hour', round((tr ->> 'working')::numeric, 3),
    'labor_nominal', round((tr ->> 'nominal')::numeric, 3),
    'labor_cap_hours', (public.config_get('farm') ->> 'labor_bank_cap_hours')::double precision,
    'nickname', pr.nickname,
    'is_admin', pr.is_admin,
    'gold', w.gold,
    'level', f.level,
    'xp', f.xp,
    'xp_to_next', (public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric,
    'last_payday', f.last_payday,
    'boosted_sale_day', f.boosted_sale_day,
    'pet_swapped_at', f.pet_swapped_at,
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', l.lot_id, 'ready_at', l.ready_at, 'purchase_n', l.purchase_n) order by l.lot_id), '[]')
      from public.owned_lots l where l.user_id = p_user),
    'plots', (select coalesce(jsonb_agg(jsonb_build_object(
        'plot_id', pl.plot_id, 'crop_id', pl.crop_id, 'state', pl.state, 'planted_crop_id', pl.planted_crop_id,
        'planted_at', pl.planted_at, 'ready_at', pl.ready_at, 'harvests_done', pl.harvests_done, 'stalled_reason', pl.stalled_reason,
        'rarity', pl.rarity) order by pl.plot_id), '[]')
      from public.plots pl where pl.user_id = p_user),
    'trees', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', t.lot_id, 'slot', t.slot, 'fruit_id', t.fruit_id,
        'planted_at', t.planted_at, 'ready_at', t.ready_at, 'rarity', t.rarity, 'rare_left', t.rare_left) order by t.lot_id, t.slot), '[]')
      from public.trees t where t.user_id = p_user),
    'silo', (select coalesce(jsonb_object_agg(s.item_id, s.qty), '{}') from public.silo s where s.user_id = p_user and s.qty > 0),
    'auto_sell', (select coalesce(jsonb_agg(s.item_id order by s.item_id), '[]') from public.silo s where s.user_id = p_user and s.auto_sell),
    'inventory', (select coalesce(jsonb_object_agg(iv.item_id, iv.qty), '{}') from public.inventory iv where iv.user_id = p_user and iv.qty > 0),
    'tools', (select coalesce(jsonb_object_agg(tl.class_id, tl.material), '{}') from public.tools tl where tl.user_id = p_user),
    'characters', v_chars,
    'animals', (select coalesce(jsonb_agg(jsonb_build_object('house_id', a.house_id, 'slot', a.slot, 'animal_id', a.animal_id, 'rarity', a.rarity,
        'state', a.state, 'cycle_start', a.cycle_start, 'ready_at', a.ready_at) order by a.house_id, a.slot), '[]')
      from public.animals a where a.user_id = p_user),
    'houses', (select jsonb_object_agg(h.key, jsonb_build_object('owned', public.house_ready(p_user, h.key, f.farm_time),
        'tier', coalesce((select ah.tier from public.animal_houses ah where ah.user_id = p_user and ah.house_id = h.key), 0),
        'slots', public.house_slots(p_user, h.key), 'bird_slots', public.house_bird_slots(p_user, h.key, f.farm_time), 'lot', public.house_lot(h.key)))
      from jsonb_each(public.config_get('animals') -> 'houses') h),
    'lake', public.lake_ready(p_user, f.farm_time),
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('pet_id', p.pet_id, 'affinity', p.affinity, 'last_care', p.last_care,
        'active', p.active, 'linked_class', p.linked_class) order by p.adopted_at), '[]') from public.pets p where p.user_id = p_user),
    'pet', fx -> 'pet',
    'snack_prices', v_snacks,
    'fx', jsonb_build_object('stall_ratio', fx -> 'stall_ratio', 'seed_discount', fx -> 'seed_discount', 'sales_gold', fx -> 'sales_gold',
        'shop_discount', fx -> 'shop_discount', 'auto_sell', fx -> 'auto_sell', 'auto_pay', fx -> 'auto_pay', 'rare_seed', fx -> 'rare_seed',
        'seed_refund', fx -> 'seed_refund', 'gerente_cut', fx -> 'gerente_cut', 'early_unlock', fx -> 'early_unlock', 'daily_boost', fx -> 'daily_boost',
        'growth_crop', fx -> 'growth_crop', 'growth_orchard', fx -> 'growth_orchard', 'tree_initial', fx -> 'tree_initial', 'cleanup', fx -> 'cleanup',
        'tool_cost', fx -> 'tool_cost', 'harvest_xp', fx -> 'harvest_xp', 'golden', fx -> 'golden',
        'feed_discount', fx -> 'feed_discount', 'animal_production', fx -> 'animal_production', 'animal_cap', fx -> 'animal_cap',
        'animal_double', fx -> 'animal_double', 'expansion_cost', fx -> 'expansion_cost', 'rancheira', fx -> 'rancheira',
        'exp_success', fx -> 'exp_success', 'exp_duration', fx -> 'exp_duration', 'vehicle_wear', fx -> 'vehicle_wear', 'dog_recover', fx -> 'dog_recover',
        'char_xp', fx -> 'char_xp', 'account_xp', fx -> 'account_xp')
  ) into base
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user;
  return base || public.exp_state(p_user) || public.cards_state(p_user) || public.social_badge(p_user);
end;
$function$;
