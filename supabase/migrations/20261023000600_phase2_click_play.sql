-- Fase 2 (ajuste do teste do dono): com o jogo aberto, o jogador planta e colhe por clique sem gastar
-- trabalho; fora do jogo, o Agricultor faz tudo na fila, gastando 0,5 para plantar e 0,5 para colher.
-- A colheita deixa de ser automática: o canteiro maduro espera o clique ou o Agricultor.
-- Também: painel do admin pode dar nível e ouro (para testes), sempre com justificativa e auditoria.

-- ---------- avanço da fazenda: tudo na fila do Agricultor ----------
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
  v_plant_cost double precision := coalesce((v_work ->> 'plant')::double precision, 0.5);
  v_harvest_cost double precision := coalesce((v_work ->> 'harvest')::double precision, 0.5);
  v_rate double precision := public.labor_rate(p_user);
  v_cap double precision;
  v_end timestamptz;
  t0 double precision; t1 double precision;
  t_cur double precision; labor double precision;
  v_gold numeric; v_seed_spent numeric := 0; v_plantings int := 0;
  e record; c jsonb;
  lt double precision; te double precision; v_seed numeric;
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
    exit when i > 20000 or v_rate <= 0; -- trava de segurança
    -- próxima tarefa da fila (a que ficou disponível primeiro)
    select * into e from (
      select 'harvest'::text as kind, pl.plot_id as key, 0 as slot, pl.ready_at as avail, v_harvest_cost as cost
        from public.plots pl
        where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= t1
      union all
      select 'harvest_tree', tr.lot_id, tr.slot, tr.ready_at, v_harvest_cost
        from public.trees tr
        where tr.user_id = p_user and tr.fruit_id is not null and tr.ready_at <= t1
      union all
      -- plantio: o canteiro só fica livre depois da limpeza do lote
      select 'plant', pl.plot_id, 0, greatest(coalesce(pl.free_since, t0), ol.ready_at), v_plant_cost
        from public.plots pl join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
        where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and pl.stalled_reason is null
          and greatest(coalesce(pl.free_since, t0), ol.ready_at) <= t1
    ) q
    order by avail, key, slot
    limit 1;
    exit when not found;

    -- quando o Agricultor terá o trabalho necessário
    lt := least(v_cap, labor + v_rate * (greatest(e.avail, t_cur) - t_cur));
    te := case when lt >= e.cost then greatest(e.avail, t_cur) else greatest(e.avail, t_cur) + (e.cost - lt) / v_rate end;
    exit when te > t1; -- a fila é única: se a primeira tarefa não cabe, nenhuma cabe

    if e.kind = 'plant' then
      c := public.crop_def((select crop_id from public.plots where user_id = p_user and plot_id = e.key));
      v_seed := (c ->> 'seed_cost')::numeric;
      if v_gold - v_seed_spent < v_seed then
        update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = e.key;
        continue;
      end if;
      v_seed_spent := v_seed_spent + v_seed;
      v_plantings := v_plantings + 1;
      update public.plots
        set state = 'growing', planted_crop_id = crop_id, planted_kind = c ->> 'kind', planted_at = te, harvests_done = 0,
            ready_at = te + (c ->> 'grow_minutes')::double precision * 60, free_since = null
        where user_id = p_user and plot_id = e.key;
    elsif e.kind = 'harvest' then
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

-- ---------- trabalho do jogador (clique): colher e plantar sem gastar trabalho ----------
-- p_target: canteiro (A1-3), lote (A1, P1) ou null para a fazenda inteira.
create or replace function public.tend_plots(p_user uuid, p_target text, p_harvest boolean, p_plant boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_time double precision;
  v_gold numeric; v_seed_spent numeric := 0; v_plantings int := 0; v_seed numeric;
  r record; c jsonb;
begin
  select farm_time into v_time from public.farms where user_id = p_user for update;
  if p_harvest then
    for r in select pl.plot_id from public.plots pl
             where pl.user_id = p_user and pl.state = 'growing' and pl.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      perform public.harvest_plot(p_user, r.plot_id, v_time);
    end loop;
    for r in select tr.lot_id, tr.slot from public.trees tr
             where tr.user_id = p_user and tr.fruit_id is not null and tr.ready_at <= v_time
               and (p_target is null or tr.lot_id = p_target)
             order by tr.lot_id, tr.slot loop
      perform public.harvest_tree(p_user, r.lot_id, r.slot, v_time);
    end loop;
  end if;
  if p_plant then
    select gold into v_gold from public.wallets where user_id = p_user for update;
    for r in select pl.plot_id, pl.crop_id from public.plots pl
             join public.owned_lots ol on ol.user_id = pl.user_id and ol.lot_id = split_part(pl.plot_id, '-', 1)
             where pl.user_id = p_user and pl.state = 'empty' and pl.crop_id is not null and ol.ready_at <= v_time
               and (p_target is null or pl.plot_id = p_target or pl.plot_id like p_target || '-%')
             order by pl.plot_id loop
      c := public.crop_def(r.crop_id);
      v_seed := (c ->> 'seed_cost')::numeric;
      if v_gold - v_seed_spent < v_seed then
        update public.plots set stalled_reason = 'sem_ouro' where user_id = p_user and plot_id = r.plot_id;
        continue;
      end if;
      v_seed_spent := v_seed_spent + v_seed;
      v_plantings := v_plantings + 1;
      update public.plots
        set state = 'growing', planted_crop_id = crop_id, planted_kind = c ->> 'kind', planted_at = v_time, harvests_done = 0,
            ready_at = v_time + (c ->> 'grow_minutes')::double precision * 60, free_since = null, stalled_reason = null
        where user_id = p_user and plot_id = r.plot_id;
    end loop;
    if v_seed_spent > 0 then
      perform public.ledger_post(p_user, -round(v_seed_spent, 2), 'seeds',
        jsonb_build_object('plantings', v_plantings, 'farm_time', round(v_time::numeric, 1), 'by', 'player'));
    end if;
  end if;
end;
$$;

-- RPC do jogo: colher o que está maduro e plantar o que está vazio (canteiro, lote ou fazenda inteira)
create or replace function public.tend_farm(p_target text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is not null and (length(p_target) > 8 or p_target !~ '^[A-Z][0-9]{0,2}(-[0-9]{1,2})?$') then
    raise exception 'canteiro não encontrado' using errcode = 'check_violation';
  end if;
  perform public.touch_farm(v_user);
  perform public.tend_plots(v_user, p_target, true, true);
  return public.farm_state(v_user);
end;
$$;

-- escolher cultivo: canteiro vazio já é plantado na hora (o jogador está com o jogo aberto)
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
  if p_target is null or length(p_target) > 8 or p_target !~ '^[A-Z][0-9]{0,2}(-[0-9]{1,2})?$' then
    raise exception 'canteiro não encontrado' using errcode = 'check_violation';
  end if;
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
  if p_crop is not null then perform public.tend_plots(v_user, p_target, false, true); end if;
  return public.farm_state(v_user);
end;
$$;

-- ---------- admin: nível e ouro para testes (com justificativa, ficam na auditoria) ----------
create or replace function public.admin_set_level(p_user uuid, p_level int, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard(); v_from int;
begin
  if p_level is null or p_level < 1 or p_level > 50 then raise exception 'nível inválido' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  select level into v_from from public.farms where user_id = p_user for update;
  if not found then raise exception 'fazenda não encontrada' using errcode = 'check_violation'; end if;
  update public.farms set level = p_level, xp = 0 where user_id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.set_level', p_user, jsonb_build_object('from', v_from, 'to', p_level, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

create or replace function public.admin_grant_gold(p_user uuid, p_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000000 then raise exception 'valor inválido' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_reason)), 0) < 5 then raise exception 'escreva a justificativa' using errcode = 'check_violation'; end if;
  perform public.ledger_post(p_user, round(p_amount, 2), 'admin_grant', jsonb_build_object('admin', v_admin, 'reason', p_reason));
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (v_admin, 'admin.grant_gold', p_user, jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return public.farm_state(p_user);
end;
$$;

-- ---------- permissões ----------
revoke all on function public.advance_farm(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.tend_plots(uuid, text, boolean, boolean) from public, anon, authenticated;
revoke all on function public.tend_farm(text) from public, anon;
revoke all on function public.set_crop(text, text) from public, anon;
revoke all on function public.admin_set_level(uuid, int, text) from public, anon;
revoke all on function public.admin_grant_gold(uuid, numeric, text) from public, anon;
grant execute on function public.tend_farm(text) to authenticated;
grant execute on function public.set_crop(text, text) to authenticated;
grant execute on function public.admin_set_level(uuid, int, text) to authenticated;
grant execute on function public.admin_grant_gold(uuid, numeric, text) to authenticated;
