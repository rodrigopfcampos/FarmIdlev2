-- Fase 8b: Encomendas da Vila (meta coletiva semanal; doações de produção e ouro somem do jogo; cartas e títulos)
-- e Estrelas da Vila (depois do nível 50 o XP vira estrelas, que compram pacote ou semente rara junto com ouro).
-- Regras na GDD seção 9; números em config/village.json. O ranking semanal foi adiado pelo dono.

-- ---------- tabelas ----------
create table public.village_orders (
  id bigint generated always as identity primary key,
  name_pt text not null,
  items text[] not null,                                        -- os pedidos da semana (contam 1,5×)
  goal numeric(18, 2) not null,                                 -- meta coletiva em pontos
  active_players integer not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index village_orders_ends on public.village_orders (ends_at);

create table public.village_donations (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.village_orders (id) on delete restrict,
  user_id uuid not null references public.farms (user_id) on delete restrict,
  item_id text,                                                 -- null = ouro
  qty numeric(18, 2) not null,
  value numeric(18, 2) not null,                                -- ouro ou preço da Feira
  points numeric(18, 4) not null,                               -- horas da renda do nível de quem doou
  created_at timestamptz not null default now()
);
create index village_donations_order on public.village_donations (order_id, user_id);

create table public.village_rewards (
  order_id bigint not null references public.village_orders (id) on delete restrict,
  user_id uuid not null references public.farms (user_id) on delete restrict,
  points numeric(18, 4) not null,
  cards integer not null default 0,
  title text,
  created_at timestamptz not null default now(),
  primary key (order_id, user_id)
);

create table public.star_purchases (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.farms (user_id) on delete restrict,
  week date not null,                                           -- semana da conta (segunda no fuso da conta)
  kind text not null check (kind in ('pack', 'seed')),
  crop_id text,
  rarity text,
  stars integer not null,
  gold numeric(18, 2) not null,
  created_at timestamptz not null default now()
);
create index star_purchases_user on public.star_purchases (user_id, week);

alter table public.farms add column stars integer not null default 0;

alter table public.village_orders enable row level security;
alter table public.village_donations enable row level security;
alter table public.village_rewards enable row level security;
alter table public.star_purchases enable row level security;
revoke all on public.village_orders, public.village_donations, public.village_rewards, public.star_purchases from anon, authenticated;

-- ---------- Encomenda ----------
-- a Encomenda que vale agora; se a última acabou, abre a da semana (meta pelo número de jogadores ativos)
create or replace function public.village_order_current()
returns public.village_orders language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('village') -> 'encomenda'; o public.village_orders; v_items text[] := '{}'; t jsonb; v_pick text; n int;
  v_end timestamptz := (date_trunc('week', now() at time zone 'UTC') + interval '7 days') at time zone 'UTC';
begin
  select * into o from public.village_orders where starts_at <= now() and ends_at > now() order by id desc limit 1;
  if found then return o; end if;
  perform pg_advisory_xact_lock(hashtext('village_order'));
  select * into o from public.village_orders where starts_at <= now() and ends_at > now() order by id desc limit 1;
  if found then return o; end if;
  -- 1 pedido de cada faixa de nível (cultivos de lavoura), para todo mundo ter o que doar
  for t in select x from jsonb_array_elements(c -> 'requested_tiers') x loop
    select y ->> 'id' into v_pick from jsonb_array_elements(public.config_get('crops') -> 'crops') y
      where (y ->> 'unlock_level')::int between (t ->> 0)::int and (t ->> 1)::int and (c -> 'requested_kinds') ? (y ->> 'kind')
      order by public.rand01() limit 1;
    if v_pick is not null then v_items := v_items || v_pick; end if;
  end loop;
  select count(*) into n from public.farms where last_activity_at > now() - make_interval(days => (c ->> 'active_days')::int);
  insert into public.village_orders (name_pt, items, goal, active_players, starts_at, ends_at)
    values (c -> 'names_pt' ->> floor(public.rand01() * jsonb_array_length(c -> 'names_pt'))::int, v_items,
            greatest((c ->> 'goal_min_points')::numeric, n * (c ->> 'goal_points_per_active_player')::numeric), n, now(), v_end)
    returning * into o;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'village.order', null, jsonb_build_object('id', o.id, 'items', o.items, 'goal', o.goal, 'players', n));
  return o;
end;
$$;

-- pontos de um valor em ouro: horas da renda de referência do nível de quem doa
create or replace function public.village_points(p_user uuid, p_value numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(p_value / nullif(public.ref_income(f.level) / 24, 0), 4) from public.farms f where f.user_id = p_user
$$;

-- resultado de um jogador numa Encomenda: pontos, se passou do mínimo, se a meta foi batida e se ficou no top 10%
create or replace function public.village_result(p_order bigint, p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with c as (select public.config_get('village') -> 'encomenda' e),
  o as (select * from public.village_orders where id = p_order),
  tot as (select user_id, sum(points) pts from public.village_donations where order_id = p_order group by user_id),
  q as (select tot.* from tot, c where tot.pts >= (c.e ->> 'min_points_to_qualify')::numeric),
  r as (select user_id, pts, rank() over (order by pts desc) rk, count(*) over () n from q)
  select jsonb_build_object(
    'points', coalesce((select pts from tot where user_id = p_user), 0),
    'total', coalesce((select sum(pts) from tot), 0),
    'donors', (select count(*) from tot),
    'goal_reached', coalesce((select sum(pts) from tot), 0) >= (select goal from o),
    'qualified', exists (select 1 from q where user_id = p_user),
    'rank', (select rk from r where user_id = p_user),
    'top', coalesce((select rk <= greatest(1, ceil(n * (select (e ->> 'top_pct')::numeric from c) / 100)) from r where user_id = p_user), false))
$$;

-- título que o jogador usa nesta semana (da última Encomenda encerrada)
create or replace function public.village_title(p_user uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare o public.village_orders; r jsonb; t jsonb := public.config_get('village') -> 'encomenda' -> 'titles';
begin
  select * into o from public.village_orders where ends_at <= now() order by ends_at desc limit 1;
  if not found then return null; end if;
  r := public.village_result(o.id, p_user);
  if not (r ->> 'qualified')::boolean then return null; end if;
  if (r ->> 'top')::boolean then return t ->> 'top'; end if;
  if (r ->> 'goal_reached')::boolean then return t ->> 'participant'; end if;
  return null;
end;
$$;

-- prêmios das Encomendas encerradas em que o jogador doou (uma vez por Encomenda)
create or replace function public.village_settle(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('village') -> 'encomenda'; o record; r jsonb; n int; k int; v_title text;
begin
  for o in select vo.* from public.village_orders vo
           where vo.ends_at <= now() and exists (select 1 from public.village_donations d where d.order_id = vo.id and d.user_id = p_user)
             and not exists (select 1 from public.village_rewards w where w.order_id = vo.id and w.user_id = p_user)
           order by vo.id loop
    r := public.village_result(o.id, p_user);
    n := 0; v_title := null;
    if (r ->> 'qualified')::boolean then
      if (r ->> 'goal_reached')::boolean then n := n + (c -> 'reward' ->> 'card_if_goal_and_qualified')::int; v_title := c -> 'titles' ->> 'participant'; end if;
      if (r ->> 'top')::boolean and ((r ->> 'goal_reached')::boolean or not (c -> 'reward' ->> 'top_needs_goal')::boolean) then
        n := n + (c -> 'reward' ->> 'card_if_top')::int; v_title := c -> 'titles' ->> 'top';
      end if;
    end if;
    insert into public.village_rewards (order_id, user_id, points, cards, title) values (o.id, p_user, (r ->> 'points')::numeric, n, v_title)
      on conflict do nothing;
    if found then
      for k in 1 .. n loop perform public.draw_card(p_user, 'encomenda'); end loop;
      insert into public.audit_log (actor_id, action, target_user_id, data)
        values (null, 'village.reward', p_user, jsonb_build_object('order', o.id, 'cards', n, 'title', v_title) || r);
    end if;
  end loop;
end;
$$;

-- ---------- Estrelas ----------
create or replace function public.star_info(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with s as (select public.config_get('village') -> 'stars' st),
  f as (select * from public.farms where user_id = p_user),
  w as (select public.mission_week(public.user_day(p_user, now())) wk)
  select jsonb_build_object(
    'unlocked', f.level >= (s.st ->> 'unlock_level')::int,
    'stars', f.stars,
    'xp', case when f.level >= (s.st ->> 'unlock_level')::int then f.xp else 0 end,
    'per_star', round((public.config_get('levels') -> 'levels' -> 48 ->> 'xp_to_next')::numeric * (s.st ->> 'xp_per_star_ratio_of_level_49')::numeric, 2),
    'packs_week', (select count(*) from public.star_purchases p, w where p.user_id = p_user and p.week = w.wk and p.kind = 'pack'),
    'seeds_week', (select count(*) from public.star_purchases p, w where p.user_id = p_user and p.week = w.wk and p.kind = 'seed'),
    'R', public.ref_income(f.level))
  from f, s
$$;

-- comprar com Estrelas + ouro: pacote (sorteio normal, conta na garantia) ou semente rara (Incomum, Raro ou Lendário)
create or replace function public.star_buy(p_kind text, p_crop text default null, p_rarity text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); s jsonb := public.config_get('village') -> 'stars'; f public.farms; wk date; v_stars int; v_gold numeric; p jsonb;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  if f.level < (s ->> 'unlock_level')::int then raise exception 'estrelas liberam no nível 50' using errcode = 'check_violation'; end if;
  wk := public.mission_week(public.user_day(v_user, now()));
  if p_kind = 'pack' then
    p := s -> 'pack';
    if (select count(*) from public.star_purchases where user_id = v_user and week = wk and kind = 'pack') >= (p ->> 'per_week')::int then
      raise exception 'limite da semana atingido' using errcode = 'check_violation';
    end if;
  elsif p_kind = 'seed' then
    p := s -> 'seed' -> 'rarities' -> p_rarity;
    if p is null then raise exception 'raridade inválida' using errcode = 'check_violation'; end if;
    if public.crop_def(p_crop) is null then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
    if (select count(*) from public.star_purchases where user_id = v_user and week = wk and kind = 'seed') >= (s -> 'seed' ->> 'per_week')::int then
      raise exception 'limite da semana atingido' using errcode = 'check_violation';
    end if;
  else
    raise exception 'compra inválida' using errcode = 'check_violation';
  end if;
  v_stars := (p ->> 'stars')::int;
  v_gold := round(public.ref_income(f.level) * (p ->> 'gold_R_ratio')::numeric, 2);
  if f.stars < v_stars then raise exception 'estrelas insuficientes' using errcode = 'check_violation'; end if;
  perform public.ledger_post(v_user, -v_gold, 'star_shop', jsonb_build_object('kind', p_kind, 'crop', p_crop, 'rarity', p_rarity, 'stars', v_stars));
  update public.farms set stars = stars - v_stars where user_id = v_user;
  insert into public.star_purchases (user_id, week, kind, crop_id, rarity, stars, gold) values (v_user, wk, p_kind, p_crop, p_rarity, v_stars, v_gold);
  if p_kind = 'pack' then
    perform public.draw_card(v_user, 'estrelas');
  else
    insert into public.inventory (user_id, item_id, qty) values (v_user, 'seed:' || p_crop || ':' || p_rarity, 1)
      on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
  end if;
  return public.village_state(v_user);
end;
$$;

-- ---------- painel Vila ----------
create or replace function public.village_state(p_user uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare o public.village_orders := public.village_order_current(); last public.village_orders; c jsonb := public.config_get('village') -> 'encomenda'; v_r numeric;
begin
  select * into last from public.village_orders where ends_at <= now() order by ends_at desc limit 1;
  select public.ref_income(level) / 24 into v_r from public.farms where user_id = p_user;
  return jsonb_build_object(
    'order', jsonb_build_object('id', o.id, 'name', o.name_pt, 'items', to_jsonb(o.items), 'goal', o.goal, 'ends_at', o.ends_at, 'players', o.active_players),
    'mine', public.village_result(o.id, p_user),
    'per_unit', (select coalesce(jsonb_object_agg(s.item_id, round(public.item_price(s.item_id) / v_r
        * case when s.item_id = any (o.items) then (c ->> 'requested_bonus')::numeric else 1 end, 4)), '{}')
      from public.silo s where s.user_id = p_user and s.qty > 0 and public.item_price(s.item_id) is not null),
    'gold_per_point', round(v_r, 2),
    'last', case when last.id is null then null else jsonb_build_object('name', last.name_pt, 'result', public.village_result(last.id, p_user),
      'reward', (select to_jsonb(w) - 'user_id' from public.village_rewards w where w.order_id = last.id and w.user_id = p_user)) end,
    'title', public.village_title(p_user),
    'stars', public.star_info(p_user));
end;
$$;

create or replace function public.get_village()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  return public.village_state(v_user);
end;
$$;

-- doar: produto do Silo (preço da Feira; pedidos da semana valem 1,5×) ou ouro; tudo some do jogo
create or replace function public.village_donate(p_item text, p_qty numeric)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); c jsonb := public.config_get('village') -> 'encomenda'; o public.village_orders; v_have int; v_value numeric; v_pts numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  o := public.village_order_current();
  if p_item is null then
    v_value := round(p_qty, 2);
    perform public.ledger_post(v_user, -v_value, 'village_donation', jsonb_build_object('order', o.id));
    v_pts := public.village_points(v_user, v_value);
  else
    if p_qty <> floor(p_qty) then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
    if public.item_price(p_item) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
    select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
    if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
    update public.silo set qty = qty - p_qty::int where user_id = v_user and item_id = p_item;
    v_value := round(p_qty * public.item_price(p_item), 2);
    v_pts := public.village_points(v_user, v_value) * case when p_item = any (o.items) then (c ->> 'requested_bonus')::numeric else 1 end;
  end if;
  insert into public.village_donations (order_id, user_id, item_id, qty, value, points) values (o.id, v_user, p_item, p_qty, v_value, round(v_pts, 4));
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'village.donate', v_user, jsonb_build_object('order', o.id, 'item', p_item, 'qty', p_qty, 'value', v_value, 'points', round(v_pts, 4)));
  return public.village_state(v_user);
end;
$$;

-- ---------- painel do admin ----------
-- encerra a Encomenda agora (para testar os prêmios); a próxima abre no próximo acesso
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

-- ---------- funções que mudam na fase 8b ----------
-- depois do nível 50, o XP vira Estrelas da Vila (antes ficava parado em 0)
create or replace function public.add_xp(p_user uuid, p_xp numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_levels jsonb := public.config_get('levels') -> 'levels';
  v_level int; v_xp numeric; v_need numeric; v_start int; v_per numeric; v_stars int := 0;
begin
  select level, xp into v_level, v_xp from public.farms where user_id = p_user for update;
  v_start := v_level;
  v_xp := v_xp + p_xp;
  loop
    exit when v_level >= 50;
    v_need := (v_levels -> (v_level - 1) ->> 'xp_to_next')::numeric;
    exit when v_need is null or v_xp < v_need;
    v_xp := v_xp - v_need;
    v_level := v_level + 1;
  end loop;
  if v_level >= (public.config_get('village') -> 'stars' ->> 'unlock_level')::int then
    v_per := (v_levels -> 48 ->> 'xp_to_next')::numeric * (public.config_get('village') -> 'stars' ->> 'xp_per_star_ratio_of_level_49')::numeric;
    if v_per > 0 and v_xp >= v_per then
      v_stars := floor(v_xp / v_per)::int;
      v_xp := v_xp - v_stars * v_per;
    end if;
    v_xp := greatest(v_xp, 0);
  end if;
  update public.farms set level = v_level, xp = round(v_xp, 2), stars = stars + v_stars where user_id = p_user;
  if v_level > v_start then
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'level.up', p_user, jsonb_build_object('from', v_start, 'to', v_level));
  end if;
end;
$$;

-- a cada ação: a fazenda anda, conta como atividade e recebe os prêmios das Encomendas encerradas
create or replace function public.touch_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.advance_farm(p_user, now());
  update public.farms set last_activity_at = now() where user_id = p_user;
  perform public.village_settle(p_user);
end;
$$;

-- o título da Vila aparece junto do nome nas listas e na visita
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'level', f.level, 'likes', f.likes_total, 'title', public.village_title(p.id))
  from public.profiles p join public.farms f on f.user_id = p.id where p.id = p_user
$$;

-- o estado da fazenda leva também o título e as Estrelas (chave "village")
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
    'village', jsonb_build_object('title', public.village_title(p_user), 'stars', (select stars from public.farms where user_id = p_user)))
$$;

do $$
declare fn text;
begin
  foreach fn in array array['public.village_order_current()', 'public.village_points(uuid, numeric)', 'public.village_result(bigint, uuid)',
    'public.village_title(uuid)', 'public.village_settle(uuid)', 'public.star_info(uuid)', 'public.village_state(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
  foreach fn in array array['public.get_village()', 'public.village_donate(text, numeric)', 'public.star_buy(text, text, text)',
    'public.admin_close_village(text)', 'public.admin_grant_stars(uuid, int, text)'] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
