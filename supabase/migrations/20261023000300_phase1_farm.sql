-- Fase 1: fazenda mínima. Lote A1 com 8 canteiros, replantio automático pelo Agricultor,
-- relógio da fazenda que só anda até 8 h depois da última atividade, Silo e venda na Barraca.
-- O tempo vem sempre do servidor (now()): mudar a hora do aparelho não muda nada.

create table public.farms (
  user_id uuid primary key references public.profiles (id) on delete restrict,
  farm_time double precision not null default 0 check (farm_time >= 0),    -- segundos de tempo ativo da fazenda
  synced_at timestamptz not null default now(),                           -- instante real até onde farm_time foi calculado
  last_activity_at timestamptz not null default now(),                    -- última ação do jogador (limite offline)
  labor_bank double precision not null default 0 check (labor_bank >= 0), -- unidades de trabalho guardadas
  created_at timestamptz not null default now()
);

create table public.owned_lots (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  lot_id text not null,
  acquired_at timestamptz not null default now(),
  primary key (user_id, lot_id)
);

create table public.plots (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  plot_id text not null,               -- ex.: A1-3 (mesmo id do mapConfig)
  crop_id text,                        -- cultivo escolhido para o replantio; null = parado
  state text not null default 'empty' check (state in ('empty', 'growing')),
  planted_crop_id text,                -- o que está crescendo agora
  planted_at double precision,         -- tempo da fazenda (s)
  ready_at double precision,
  free_since double precision,         -- desde quando está vazio esperando o Agricultor
  stalled_reason text,                 -- por que parou (ex.: sem_ouro)
  primary key (user_id, plot_id),
  check ((state = 'growing') = (ready_at is not null and planted_crop_id is not null))
);

create table public.silo (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  item_id text not null,
  qty integer not null default 0 check (qty >= 0),
  primary key (user_id, item_id)
);

alter table public.farms enable row level security;
alter table public.owned_lots enable row level security;
alter table public.plots enable row level security;
alter table public.silo enable row level security;
create policy farms_read_own on public.farms for select to authenticated using (user_id = (select auth.uid()));
create policy owned_lots_read_own on public.owned_lots for select to authenticated using (user_id = (select auth.uid()));
create policy plots_read_own on public.plots for select to authenticated using (user_id = (select auth.uid()));
create policy silo_read_own on public.silo for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.farms, public.owned_lots, public.plots, public.silo from anon, authenticated;

-- ---------- criação da fazenda ----------
create or replace function public.create_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_farm jsonb := public.config_get('farm');
  v_crops jsonb := public.config_get('crops');
  v_lot text := coalesce(v_farm ->> 'starting_lot', 'A1');
  v_rate double precision := (v_crops -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision;
  k int;
begin
  insert into public.farms (user_id, labor_bank)
    values (p_user, coalesce(v_rate, 0) * coalesce((v_farm ->> 'initial_labor_bank_hours')::double precision, 0))
    on conflict do nothing;
  insert into public.owned_lots (user_id, lot_id) values (p_user, v_lot) on conflict do nothing;
  for k in 1 .. coalesce((v_farm ->> 'plots_per_crop_lot')::int, 8) loop
    insert into public.plots (user_id, plot_id) values (p_user, v_lot || '-' || k) on conflict do nothing;
  end loop;
end;
$$;

-- conta nova já ganha a fazenda (mesma regra de idade da fase 0)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nick text := nullif(trim(new.raw_user_meta_data ->> 'nickname'), '');
  v_birth date;
  v_start numeric := coalesce((public.config_get('levels') ->> 'starting_gold')::numeric, 0);
begin
  begin
    v_birth := (new.raw_user_meta_data ->> 'birth_date')::date;
  exception when others then
    v_birth := null;
  end;
  if v_birth is null or v_birth > (current_date - interval '18 years')::date then
    raise exception 'conta exige 18 anos ou mais' using errcode = 'check_violation';
  end if;
  if v_nick is null or char_length(v_nick) not between 3 and 20 then
    v_nick := 'Fazendeiro' || substr(replace(new.id::text, '-', ''), 1, 6);
  end if;
  insert into public.profiles (id, nickname, birth_date) values (new.id, v_nick, v_birth);
  insert into public.wallets (user_id) values (new.id);
  if v_start > 0 then
    perform public.ledger_post(new.id, v_start, 'starting_gold', jsonb_build_object('config', 'levels'), 'starting_gold');
  end if;
  perform public.create_farm(new.id);
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'account.created', new.id, jsonb_build_object('starting_gold', v_start));
  return new;
end;
$$;

-- dado de um cultivo na config
create or replace function public.crop_def(p_crop text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('crops') -> 'crops') x where x ->> 'id' = p_crop
$$;

-- ---------- avanço da fazenda (determinístico) ----------
-- Avança o relógio da fazenda até p_now, no máximo 8 h depois da última atividade.
-- Cada plantio gasta 1 unidade de trabalho (plantar + colher); o trabalho acumula no ritmo
-- do Agricultor, com teto de 1 h guardada. A colheita é automática e vai para o Silo.
-- Os canteiros são atendidos na ordem em que ficaram livres.
create or replace function public.advance_farm(p_user uuid, p_now timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.farms;
  v_farm jsonb := public.config_get('farm');
  v_rate double precision;            -- unidades de trabalho por segundo
  v_cap double precision;             -- teto do trabalho guardado
  v_end timestamptz;
  t0 double precision; t1 double precision;
  t_cur double precision; labor double precision;
  v_gold numeric; v_seed_spent numeric := 0; v_plantings int := 0; v_harvests int := 0;
  v_can_plant boolean := true;
  p record; c jsonb;
  tt double precision; lt double precision; v_plant double precision; v_seed numeric;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_rate := (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision / 3600.0;
  v_cap := v_rate * 3600.0 * coalesce((v_farm ->> 'labor_bank_cap_hours')::double precision, 1);
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  t_cur := t0;
  labor := f.labor_bank;
  select gold into v_gold from public.wallets where user_id = p_user for update;

  loop
    i := i + 1;
    exit when i > 10000; -- trava de segurança
    select pl.plot_id, pl.state, pl.crop_id, pl.planted_crop_id, pl.ready_at,
           case when pl.state = 'growing' then pl.ready_at else coalesce(pl.free_since, t0) end as free_at
      into p
      from public.plots pl
      where pl.user_id = p_user
        and ((pl.state = 'growing' and pl.ready_at <= t1)
          or (v_can_plant and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null))
      order by 6, pl.plot_id
      limit 1;
    exit when not found;

    if p.state = 'growing' then
      -- colheita automática
      c := public.crop_def(p.planted_crop_id);
      insert into public.silo (user_id, item_id, qty) values (p_user, p.planted_crop_id, (c ->> 'units_per_harvest')::int)
        on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
      update public.plots set state = 'empty', planted_crop_id = null, planted_at = null, ready_at = null, free_since = p.ready_at
        where user_id = p_user and plot_id = p.plot_id;
      v_harvests := v_harvests + 1;
      continue;
    end if;

    -- replantio: espera o canteiro ficar livre e o Agricultor ter 1 unidade de trabalho
    tt := greatest(p.free_at, t_cur);
    lt := least(v_cap, labor + v_rate * (tt - t_cur));
    v_plant := case when lt >= 1 then tt else tt + (1 - lt) / v_rate end;
    if v_plant > t1 then
      v_can_plant := false; -- ninguém mais planta até t1; só faltam colheitas
      continue;
    end if;
    c := public.crop_def(p.crop_id);
    v_seed := (c ->> 'seed_cost')::numeric;
    if v_gold - v_seed_spent < v_seed then
      update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = p.plot_id;
      continue;
    end if;
    -- só agora o trabalho é gasto
    labor := case when lt >= 1 then lt - 1 else 0 end;
    t_cur := v_plant;
    v_seed_spent := v_seed_spent + v_seed;
    v_plantings := v_plantings + 1;
    update public.plots
      set state = 'growing', planted_crop_id = p.crop_id, planted_at = v_plant,
          ready_at = v_plant + (c ->> 'grow_minutes')::double precision * 60, free_since = null
      where user_id = p_user and plot_id = p.plot_id;
  end loop;

  if t1 > t_cur then labor := least(v_cap, labor + v_rate * (t1 - t_cur)); end if;
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = labor where user_id = p_user;
  if v_seed_spent > 0 then
    perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds',
      jsonb_build_object('plantings', v_plantings, 'farm_time', round(t1::numeric, 1)));
  end if;
end;
$$;

-- ---------- estado para o jogo ----------
create or replace function public.farm_state(p_user uuid)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'server_now', now(),
    'farm_time', f.farm_time,
    'synced_at', f.synced_at,
    'last_activity_at', f.last_activity_at,
    'offline_cap_hours', (public.config_get('farm') ->> 'offline_cap_hours')::int,
    'labor_bank', f.labor_bank,
    'labor_per_hour', (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision,
    'labor_cap_hours', (public.config_get('farm') ->> 'labor_bank_cap_hours')::double precision,
    'nickname', pr.nickname,
    'gold', w.gold,
    'lots', (select coalesce(jsonb_agg(l.lot_id order by l.lot_id), '[]') from public.owned_lots l where l.user_id = p_user),
    'plots', (select coalesce(jsonb_agg(jsonb_build_object(
        'plot_id', pl.plot_id, 'crop_id', pl.crop_id, 'state', pl.state, 'planted_crop_id', pl.planted_crop_id,
        'planted_at', pl.planted_at, 'ready_at', pl.ready_at, 'stalled_reason', pl.stalled_reason) order by pl.plot_id), '[]')
      from public.plots pl where pl.user_id = p_user),
    'silo', (select coalesce(jsonb_object_agg(s.item_id, s.qty), '{}') from public.silo s where s.user_id = p_user and s.qty > 0)
  )
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user
$$;

-- toda ação do jogador: avança até agora e marca atividade (reinicia o limite de 8 h)
create or replace function public.touch_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.advance_farm(p_user, now());
  update public.farms set last_activity_at = now() where user_id = p_user;
end;
$$;

-- ---------- RPCs chamadas pelo jogo ----------
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
  perform public.touch_farm(v_user);
  return public.farm_state(v_user);
end;
$$;

-- escolhe o cultivo de um canteiro (ou de todos os canteiros de um lote); null para parar
create or replace function public.set_crop(p_target text, p_crop text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_allowed jsonb := public.config_get('farm') -> 'phase1_unlocked_crops';
  v_time double precision;
  n int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_crop is not null and not (v_allowed ? p_crop) then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots
    set crop_id = p_crop, stalled_reason = null,
        free_since = case when state = 'empty' then v_time else free_since end
    where user_id = v_user and (plot_id = p_target or plot_id like p_target || '-%')
      and split_part(plot_id, '-', 1) in (select lot_id from public.owned_lots where user_id = v_user);
  get diagnostics n = row_count;
  if n = 0 then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  perform public.advance_farm(v_user, now()); -- planta já, se houver trabalho guardado
  return public.farm_state(v_user);
end;
$$;

-- vende na Barraca, na hora e sem risco, a 70% do preço da Feira
create or replace function public.sell_at_stall(p_item text, p_qty int, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ratio numeric := coalesce((public.config_get('expeditions') ->> 'stall_price_ratio')::numeric, 0.7);
  v_price numeric;
  v_have int;
  v_amount numeric;
  v_time double precision;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'chave de idempotência obrigatória' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  -- mesma venda enviada duas vezes: não vende de novo
  if exists (select 1 from public.ledger where user_id = v_user and idempotency_key = p_idempotency_key) then
    return public.farm_state(v_user);
  end if;
  v_price := (public.crop_def(p_item) ->> 'fair_price_per_unit')::numeric;
  if v_price is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  select qty into v_have from public.silo where user_id = v_user and item_id = p_item for update;
  if coalesce(v_have, 0) < p_qty then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  update public.silo set qty = qty - p_qty where user_id = v_user and item_id = p_item;
  v_amount := round(p_qty * v_price * v_ratio, 2);
  perform public.ledger_post(v_user, v_amount, 'stall_sale', jsonb_build_object('item', p_item, 'qty', p_qty, 'price', v_price, 'ratio', v_ratio), p_idempotency_key);
  -- quem tinha parado por falta de ouro volta a plantar a partir de agora
  select farm_time into v_time from public.farms where user_id = v_user;
  update public.plots set stalled_reason = null, free_since = v_time where user_id = v_user and stalled_reason = 'sem_ouro';
  perform public.advance_farm(v_user, now());
  return public.farm_state(v_user);
end;
$$;

-- fazendas de quem já tinha conta
do $$
declare u record;
begin
  for u in select id from public.profiles loop perform public.create_farm(u.id); end loop;
end $$;

-- ---------- permissões das funções ----------
revoke all on function public.create_farm(uuid) from public, anon, authenticated;
revoke all on function public.advance_farm(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.farm_state(uuid) from public, anon, authenticated;
revoke all on function public.touch_farm(uuid) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.get_farm() from public, anon;
revoke all on function public.set_crop(text, text) from public, anon;
revoke all on function public.sell_at_stall(text, int, text) from public, anon;
grant execute on function public.get_farm() to authenticated;
grant execute on function public.set_crop(text, text) to authenticated;
grant execute on function public.sell_at_stall(text, int, text) to authenticated;
