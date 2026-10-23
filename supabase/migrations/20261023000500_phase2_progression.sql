-- Fase 2: progressão. XP e níveis 1–50, os 50 cultivos (lavoura e recorrentes), compra e limpeza
-- dos 29 lotes (vizinhança, nível, Escritura da 20ª compra em diante), pomar com troca grátis de árvore
-- e melhoria da ferramenta do Agricultor na Forja. Números só da config (game_config).

alter table public.farms add column level integer not null default 1 check (level between 1 and 50);
alter table public.farms add column xp numeric(18, 2) not null default 0 check (xp >= 0);

alter table public.owned_lots add column ready_at double precision not null default 0; -- fim da limpeza (tempo da fazenda)
alter table public.owned_lots add column purchase_n integer;                            -- nª compra (null = lote inicial)

alter table public.plots add column harvests_done integer not null default 0;            -- colheitas do plantio atual (recorrentes)
alter table public.plots add column planted_kind text;                                     -- crop ou recurring (evita ler a config a cada evento)
update public.plots set planted_kind = 'crop' where state = 'growing';

create table public.trees (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  lot_id text not null,
  slot integer not null check (slot between 1 and 4),
  fruit_id text,                -- null = vaga vazia
  planted_at double precision,  -- tempo da fazenda
  ready_at double precision,    -- próxima colheita
  primary key (user_id, lot_id, slot),
  check ((fruit_id is null) = (ready_at is null))
);

create table public.inventory (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  item_id text not null,        -- ex.: deed (Escritura)
  qty integer not null default 0 check (qty >= 0),
  primary key (user_id, item_id)
);

create table public.tools (
  user_id uuid not null references public.farms (user_id) on delete restrict,
  class_id text not null,       -- agricultor, rancheira...
  material text not null default 'wood',
  primary key (user_id, class_id)
);

alter table public.trees enable row level security;
alter table public.inventory enable row level security;
alter table public.tools enable row level security;
create policy trees_read_own on public.trees for select to authenticated using (user_id = (select auth.uid()));
create policy inventory_read_own on public.inventory for select to authenticated using (user_id = (select auth.uid()));
create policy tools_read_own on public.tools for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.trees, public.inventory, public.tools from anon, authenticated;

insert into public.tools (user_id, class_id) select user_id, 'agricultor' from public.farms on conflict do nothing;

-- ---------- ajudantes de config ----------
create or replace function public.lot_def(p_lot text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x from jsonb_array_elements(public.config_get('map_rules') -> 'lots') x where x ->> 'id' = p_lot
$$;

-- unidades de trabalho por segundo: base da config × material da ferramenta do Agricultor
create or replace function public.labor_rate(p_user uuid)
returns double precision
language sql stable
security definer
set search_path = ''
as $$
  select (public.config_get('crops') -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision / 3600.0
       * coalesce((select (m ->> 'work_capacity_multiplier')::double precision
                   from jsonb_array_elements(public.config_get('tools_and_items') -> 'tool_materials') m
                   where m ->> 'id' = (select material from public.tools where user_id = p_user and class_id = 'agricultor')), 1)
$$;

-- soma XP e sobe de nível (tabela de config/levels.json)
create or replace function public.add_xp(p_user uuid, p_xp numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_levels jsonb := public.config_get('levels') -> 'levels';
  v_level int; v_xp numeric; v_need numeric; v_start int;
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
  if v_level = 50 then v_xp := least(v_xp, 0); end if; -- depois do 50, o XP vira Estrelas da Vila (fase futura)
  update public.farms set level = v_level, xp = round(v_xp, 2) where user_id = p_user;
  if v_level > v_start then
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'level.up', p_user, jsonb_build_object('from', v_start, 'to', v_level));
  end if;
end;
$$;

-- ---------- avanço da fazenda (fase 2) ----------
-- Eventos em ordem de tempo:
--   * colheita que já foi paga no plantio (lavoura, 1ª do recorrente): na hora em que fica pronta;
--   * tarefas que gastam trabalho, na ordem em que ficaram disponíveis (fila única):
--       plantar (1 unidade + semente), colheita extra do recorrente e colheita de árvore (0,5).
-- Sem trabalho suficiente antes do fim do intervalo, a fila para; as colheitas pagas continuam.
create or replace function public.advance_farm(p_user uuid, p_now timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.farms;
  v_farm jsonb := public.config_get('farm');
  v_work jsonb := public.config_get('crops') -> 'rules' -> 'work_units';
  v_plant_cost double precision := coalesce((v_work ->> 'plant_and_harvest')::double precision, 1);
  v_extra_cost double precision := coalesce((v_work ->> 'extra_harvest_recurring_or_tree')::double precision, 0.5);
  v_rate double precision := public.labor_rate(p_user);
  v_cap double precision;
  v_end timestamptz;
  t0 double precision; t1 double precision;
  t_cur double precision; labor double precision;
  v_gold numeric; v_seed_spent numeric := 0; v_sapling numeric := 0; v_plantings int := 0;
  v_labor_open boolean := true;
  e record; c jsonb;
  lt double precision; te double precision; v_seed numeric; v_t double precision;
  i int := 0;
begin
  select * into f from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada'; end if;
  v_cap := v_rate * 3600.0 * coalesce((v_farm ->> 'labor_bank_cap_hours')::double precision, 1);
  v_end := least(p_now, f.last_activity_at + make_interval(hours => coalesce((v_farm ->> 'offline_cap_hours')::int, 8)));
  t0 := f.farm_time;
  t1 := f.farm_time + greatest(0, extract(epoch from (v_end - f.synced_at)));
  t_cur := t0;
  labor := f.labor_bank;
  select gold into v_gold from public.wallets where user_id = p_user for update;

  loop
    i := i + 1;
    exit when i > 20000; -- trava de segurança
    select * into e from (
      -- colheitas já pagas
      select 'harvest_paid'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, 0::double precision as cost
        from public.plots pl
        where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= t1
          and (pl.harvests_done = 0 or pl.planted_kind = 'crop')
      union all
      -- colheita extra de recorrente
      select 'harvest_extra', pl.plot_id, 0, pl.ready_at, v_extra_cost
        from public.plots pl
        where v_labor_open and pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= t1 and pl.harvests_done > 0
          and pl.planted_kind = 'recurring'
      union all
      -- colheita de árvore
      select 'harvest_tree', tr.lot_id, tr.slot, tr.ready_at, v_extra_cost
        from public.trees tr
        where v_labor_open and tr.user_id = p_user and tr.fruit_id is not null and tr.ready_at <= t1
      union all
      -- plantio (o canteiro só fica livre depois da limpeza do lote)
      select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost
        from public.plots pl join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
        where v_labor_open and pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null
    ) q
    order by avail, case kind when 'harvest_paid' then 0 else 1 end, key, slot
    limit 1;
    exit when not found;

    if e.kind = 'harvest_paid' then
      perform public.harvest_plot(p_user, e.key, e.avail);
      continue;
    end if;

    -- tarefa com trabalho: quando o Agricultor terá o trabalho necessário
    lt := least(v_cap, labor + v_rate * (greatest(e.avail, t_cur) - t_cur));
    te := case when lt >= e.cost then greatest(e.avail, t_cur) else greatest(e.avail, t_cur) + (e.cost - lt) / v_rate end;
    if te > t1 or v_rate <= 0 then
      v_labor_open := false;
      continue;
    end if;

    if e.kind = 'plant' then
      c := public.crop_def((select crop_id from public.plots where user_id = p_user and plot_id = e.key));
      v_seed := (c ->> 'seed_cost')::numeric;
      if v_gold - v_seed_spent - v_sapling < v_seed then
        update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
        continue;
      end if;
      v_seed_spent := v_seed_spent + v_seed;
      v_plantings := v_plantings + 1;
      update public.plots
        set state = 'growing', planted_crop_id = crop_id, planted_kind = c ->> 'kind', planted_at = te, harvests_done = 0,
            ready_at = te + (c ->> 'grow_minutes')::double precision * 60, free_since = null
        where user_id = p_user and plot_id = e.key;
    elsif e.kind = 'harvest_extra' then
      perform public.harvest_plot(p_user, e.key, te);
    else
      perform public.harvest_tree(p_user, e.key, e.slot, te);
    end if;
    labor := lt - e.cost;
    t_cur := te;
  end loop;

  if t1 > t_cur then labor := least(v_cap, labor + v_rate * (t1 - t_cur)); end if;
  update public.farms set farm_time = t1, synced_at = p_now, labor_bank = greatest(0, labor) where user_id = p_user;
  if v_seed_spent > 0 then
    perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds',
      jsonb_build_object('plantings', v_plantings, 'farm_time', round(t1::numeric, 1)));
  end if;
end;
$$;

-- colhe um canteiro no instante p_t (tempo da fazenda)
create or replace function public.harvest_plot(p_user uuid, p_plot text, p_t double precision)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  pl public.plots; c jsonb; v_done int; v_total int;
begin
  select * into pl from public.plots where user_id = p_user and plot_id = p_plot for update;
  c := public.crop_def(pl.planted_crop_id);
  insert into public.silo (user_id, item_id, qty) values (p_user, pl.planted_crop_id, (c ->> 'units_per_harvest')::int)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.add_xp(p_user, (c ->> 'xp_per_harvest')::numeric);
  v_done := pl.harvests_done + 1;
  v_total := coalesce((c ->> 'harvests_per_planting')::int, 1);
  if (c ->> 'kind') = 'recurring' and v_done < v_total then
    update public.plots set harvests_done = v_done, ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60
      where user_id = p_user and plot_id = p_plot;
  else
    update public.plots set state = 'empty', planted_crop_id = null, planted_kind = null, planted_at = null, ready_at = null,
        harvests_done = 0, free_since = p_t
      where user_id = p_user and plot_id = p_plot;
  end if;
end;
$$;

create or replace function public.harvest_tree(p_user uuid, p_lot text, p_slot int, p_t double precision)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare tr public.trees; c jsonb;
begin
  select * into tr from public.trees where user_id = p_user and lot_id = p_lot and slot = p_slot for update;
  c := public.crop_def(tr.fruit_id);
  insert into public.silo (user_id, item_id, qty) values (p_user, tr.fruit_id, (c ->> 'units_per_harvest')::int)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  perform public.add_xp(p_user, (c ->> 'xp_per_harvest')::numeric);
  update public.trees set ready_at = p_t + (c ->> 'regrow_minutes')::double precision * 60
    where user_id = p_user and lot_id = p_lot and slot = p_slot;
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
    'labor_per_hour', public.labor_rate(p_user) * 3600,
    'labor_cap_hours', (public.config_get('farm') ->> 'labor_bank_cap_hours')::double precision,
    'nickname', pr.nickname,
    'is_admin', pr.is_admin,
    'gold', w.gold,
    'level', f.level,
    'xp', f.xp,
    'xp_to_next', (public.config_get('levels') -> 'levels' -> (f.level - 1) ->> 'xp_to_next')::numeric,
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', l.lot_id, 'ready_at', l.ready_at, 'purchase_n', l.purchase_n) order by l.lot_id), '[]')
      from public.owned_lots l where l.user_id = p_user),
    'plots', (select coalesce(jsonb_agg(jsonb_build_object(
        'plot_id', pl.plot_id, 'crop_id', pl.crop_id, 'state', pl.state, 'planted_crop_id', pl.planted_crop_id,
        'planted_at', pl.planted_at, 'ready_at', pl.ready_at, 'harvests_done', pl.harvests_done, 'stalled_reason', pl.stalled_reason) order by pl.plot_id), '[]')
      from public.plots pl where pl.user_id = p_user),
    'trees', (select coalesce(jsonb_agg(jsonb_build_object('lot_id', t.lot_id, 'slot', t.slot, 'fruit_id', t.fruit_id,
        'planted_at', t.planted_at, 'ready_at', t.ready_at) order by t.lot_id, t.slot), '[]')
      from public.trees t where t.user_id = p_user),
    'silo', (select coalesce(jsonb_object_agg(s.item_id, s.qty), '{}') from public.silo s where s.user_id = p_user and s.qty > 0),
    'inventory', (select coalesce(jsonb_object_agg(iv.item_id, iv.qty), '{}') from public.inventory iv where iv.user_id = p_user and iv.qty > 0),
    'tools', (select coalesce(jsonb_object_agg(tl.class_id, tl.material), '{}') from public.tools tl where tl.user_id = p_user)
  )
  from public.farms f
  join public.profiles pr on pr.id = f.user_id
  join public.wallets w on w.user_id = f.user_id
  where f.user_id = p_user
$$;

-- ---------- criação da fazenda (agora também a ferramenta) ----------
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
  insert into public.tools (user_id, class_id) values (p_user, 'agricultor') on conflict do nothing;
end;
$$;

-- ---------- RPCs do jogo ----------
-- escolher cultivo: agora pelo nível (lavoura e recorrente; pomar usa plant_tree)
create or replace function public.set_crop(p_target text, p_crop text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_time double precision;
  v_level int;
  c jsonb;
  n int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if p_crop is not null then
    c := public.crop_def(p_crop);
    if c is null or (c ->> 'kind') = 'orchard' then raise exception 'cultivo inválido' using errcode = 'check_violation'; end if;
    if (c ->> 'unlock_level')::int > v_level then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  end if;
  update public.plots
    set crop_id = p_crop, stalled_reason = null,
        free_since = case when state = 'empty' then v_time else free_since end
    where user_id = v_user and (plot_id = p_target or plot_id like p_target || '-%')
      and split_part(plot_id, '-', 1) in (select lot_id from public.owned_lots where user_id = v_user);
  get diagnostics n = row_count;
  if n = 0 then raise exception 'canteiro não encontrado' using errcode = 'check_violation'; end if;
  perform public.advance_farm(v_user, now());
  return public.farm_state(v_user);
end;
$$;

-- comprar lote: vizinhança (ou pasto isento), nível, ouro e Escritura; depois vem a limpeza
create or replace function public.buy_lot(p_lot text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_lots jsonb := public.config_get('lots');
  v_map jsonb := public.config_get('map_rules');
  v_lot jsonb := public.lot_def(p_lot);
  v_n int; v_row jsonb; v_need_level int; v_level int; v_cost numeric; v_deed boolean;
  v_time double precision; v_minutes double precision; v_ready double precision;
  v_neighbor boolean; k int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if v_lot is null then raise exception 'lote não existe' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  if exists (select 1 from public.owned_lots where user_id = v_user and lot_id = p_lot) then
    raise exception 'esse lote já é seu' using errcode = 'check_violation';
  end if;
  select count(*) into v_n from public.owned_lots where user_id = v_user; -- o inicial conta: a próxima compra é a nª
  v_row := v_lots -> 'purchases' -> (v_n - 1);
  if v_row is null then raise exception 'todos os lotes já foram comprados' using errcode = 'check_violation'; end if;
  -- vizinhança: divide um lado com um lote seu; Galinheiro e Celeiro são isentos
  v_neighbor := (v_map -> 'exempt_types') ? (v_lot ->> 'type')
    or exists (select 1 from jsonb_array_elements_text(v_lot -> 'neighbors') nb
               join public.owned_lots ol on ol.user_id = v_user and ol.lot_id = nb);
  if not v_neighbor then raise exception 'lote não é vizinho' using errcode = 'check_violation'; end if;
  select level, farm_time into v_level, v_time from public.farms where user_id = v_user;
  v_need_level := greatest((v_row ->> 'min_level')::int, coalesce((v_lots -> 'rules' -> 'min_level' -> 'type_floor' ->> (v_lot ->> 'type'))::int, 0));
  if v_level < v_need_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  v_deed := (v_row ->> 'requires_deed')::boolean;
  if v_deed then
    update public.inventory set qty = qty - 1 where user_id = v_user and item_id = 'deed' and qty >= 1;
    if not found then raise exception 'precisa de Escritura' using errcode = 'check_violation'; end if;
  end if;
  v_cost := (v_row ->> 'cost')::numeric;
  perform public.ledger_post(v_user, -v_cost, 'lot_purchase', jsonb_build_object('lot', p_lot, 'n', v_n, 'deed', v_deed), 'lot:' || p_lot);
  -- limpeza: sem Ferreiro (até a fase 3), outra classe leva o multiplicador da config
  v_minutes := ((v_lots -> 'rules' -> 'cleanup' ->> 'base_minutes')::double precision
               + (v_lots -> 'rules' -> 'cleanup' ->> 'per_purchase_minutes')::double precision * v_n)
               * (v_lots -> 'rules' -> 'cleanup' ->> 'other_class_multiplier')::double precision;
  v_ready := v_time + v_minutes * 60;
  insert into public.owned_lots (user_id, lot_id, ready_at, purchase_n) values (v_user, p_lot, v_ready, v_n);
  for k in 1 .. jsonb_array_length(coalesce(v_lot -> 'plots', '[]')) loop
    insert into public.plots (user_id, plot_id, free_since) values (v_user, v_lot -> 'plots' ->> (k - 1), v_ready);
  end loop;
  for k in 1 .. coalesce((v_lot ->> 'tree_slots')::int, 0) loop
    insert into public.trees (user_id, lot_id, slot) values (v_user, p_lot, k);
  end loop;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'lot.bought', v_user, jsonb_build_object('lot', p_lot, 'n', v_n, 'cost', v_cost, 'deed', v_deed, 'cleanup_minutes', v_minutes));
  return public.farm_state(v_user);
end;
$$;

-- plantar muda no pomar (troca a árvore que estiver lá; derrubar é grátis)
create or replace function public.plant_tree(p_lot text, p_slot int, p_fruit text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  c jsonb := public.crop_def(p_fruit);
  v_time double precision; v_level int; v_ready double precision; v_cost numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if c is null or (c ->> 'kind') <> 'orchard' then raise exception 'fruta inválida' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  select farm_time, level into v_time, v_level from public.farms where user_id = v_user;
  if (c ->> 'unlock_level')::int > v_level then raise exception 'cultivo não liberado' using errcode = 'check_violation'; end if;
  select ready_at into v_ready from public.owned_lots where user_id = v_user and lot_id = p_lot;
  if v_ready is null or not exists (select 1 from public.trees where user_id = v_user and lot_id = p_lot and slot = p_slot) then
    raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation';
  end if;
  if v_ready > v_time then raise exception 'lote ainda em limpeza' using errcode = 'check_violation'; end if;
  v_cost := (c ->> 'sapling_cost')::numeric;
  perform public.ledger_post(v_user, -v_cost, 'sapling', jsonb_build_object('lot', p_lot, 'slot', p_slot, 'fruit', p_fruit));
  update public.trees set fruit_id = p_fruit, planted_at = v_time, ready_at = v_time + (c ->> 'grow_minutes')::double precision * 60
    where user_id = v_user and lot_id = p_lot and slot = p_slot;
  return public.farm_state(v_user);
end;
$$;

create or replace function public.chop_tree(p_lot text, p_slot int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  update public.trees set fruit_id = null, planted_at = null, ready_at = null where user_id = v_user and lot_id = p_lot and slot = p_slot;
  if not found then raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;

-- melhorar a ferramenta (fase 2: só a Enxada do Agricultor; o Ferreiro e o desgaste entram na fase 3)
create or replace function public.upgrade_tool(p_class text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_mats jsonb := public.config_get('tools_and_items') -> 'tool_materials';
  v_cur text; v_idx int; v_next jsonb; v_level int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select material into v_cur from public.tools where user_id = v_user and class_id = p_class for update;
  if v_cur is null then raise exception 'ferramenta não encontrada' using errcode = 'check_violation'; end if;
  select ord - 1 into v_idx from jsonb_array_elements(v_mats) with ordinality as m(x, ord) where x ->> 'id' = v_cur;
  v_next := v_mats -> (v_idx + 1);
  if v_next is null then raise exception 'ferramenta já está no máximo' using errcode = 'check_violation'; end if;
  select level into v_level from public.farms where user_id = v_user;
  if (v_next ->> 'unlock_level')::int > v_level then raise exception 'nível insuficiente' using errcode = 'check_violation'; end if;
  perform public.ledger_post(v_user, -(v_next ->> 'upgrade_cost_gold')::numeric, 'tool_upgrade',
    jsonb_build_object('class', p_class, 'from', v_cur, 'to', v_next ->> 'id'), 'tool:' || p_class || ':' || (v_next ->> 'id'));
  update public.tools set material = v_next ->> 'id' where user_id = v_user and class_id = p_class;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_user, 'tool.upgraded', v_user, jsonb_build_object('class', p_class, 'to', v_next ->> 'id'));
  return public.farm_state(v_user);
end;
$$;

-- vender na Barraca: agora vale também para frutas (mesma regra)
-- (sell_at_stall da fase 1 já usa crop_def, que inclui as frutas)

-- admin: dar item (Escritura) com justificativa; fica no audit_log
create or replace function public.admin_grant_item(p_user uuid, p_item text, p_qty int, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if p_item not in ('deed') then raise exception 'item desconhecido' using errcode = 'check_violation'; end if;
  if p_qty is null or p_qty = 0 or abs(p_qty) > 10 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  insert into public.inventory (user_id, item_id, qty) values (p_user, p_item, greatest(p_qty, 0))
    on conflict (user_id, item_id) do update set qty = public.inventory.qty + p_qty;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_item', p_user, jsonb_build_object('item', p_item, 'qty', p_qty, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- ---------- permissões ----------
revoke all on function public.lot_def(text) from public, anon, authenticated;
revoke all on function public.labor_rate(uuid) from public, anon, authenticated;
revoke all on function public.add_xp(uuid, numeric) from public, anon, authenticated;
revoke all on function public.harvest_plot(uuid, text, double precision) from public, anon, authenticated;
revoke all on function public.harvest_tree(uuid, text, int, double precision) from public, anon, authenticated;
revoke all on function public.advance_farm(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.farm_state(uuid) from public, anon, authenticated;
revoke all on function public.create_farm(uuid) from public, anon, authenticated;
revoke all on function public.set_crop(text, text) from public, anon;
revoke all on function public.buy_lot(text) from public, anon;
revoke all on function public.plant_tree(text, int, text) from public, anon;
revoke all on function public.chop_tree(text, int) from public, anon;
revoke all on function public.upgrade_tool(text) from public, anon;
revoke all on function public.admin_grant_item(uuid, text, int, text) from public, anon;
grant execute on function public.set_crop(text, text) to authenticated;
grant execute on function public.buy_lot(text) to authenticated;
grant execute on function public.plant_tree(text, int, text) to authenticated;
grant execute on function public.chop_tree(text, int) to authenticated;
grant execute on function public.upgrade_tool(text) to authenticated;
grant execute on function public.admin_grant_item(uuid, text, int, text) to authenticated;
