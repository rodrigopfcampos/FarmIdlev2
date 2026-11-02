-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.exp_resolve(p_id uuid, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x public.expeditions; e jsonb := public.config_get('expeditions'); r jsonb; lead jsonb; u double precision; pc double precision;
  v_out text; v_gold numeric := 0; v_refund numeric := 0; v_loss double precision; v_back jsonb := '{}'; v_drops jsonb := '[]';
  v_rolls int := 1; k int; c record; v_lost int; v_rec boolean := false; v_txt text;
begin
  select * into x from public.expeditions where id = p_id for update;
  r := public.exp_route(x.route_id);
  if x.led then lead := public.lead_info(x.user_id); end if;
  u := public.rand01();
  -- crítico: base + Gerente + Estrada Livre/Trevo/Armory gravados na saída (teto absoluto da GDD)
  pc := least(x.chance, coalesce((public.config_get('cards') -> 'bonus_caps' -> 'expedition_crit_pct' ->> 'absolute')::double precision, 60) / 100,
              (e -> 'crit' ->> 'chance')::double precision + (coalesce((lead ->> 'crit_pts')::double precision, 0) + public.jnum(x.card_fx, 'crit_pts')) / 100);
  if u < pc then v_out := 'crit'; elsif u < x.chance then v_out := 'success'; else v_out := 'fail'; end if;

  if v_out = 'crit' then
    v_gold := round(x.cargo_value * (1 + (e -> 'crit' ->> 'bonus_value')::numeric * (1 + public.jnum(x.card_fx, 'crit_val')::numeric / 100)) * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
    v_rolls := (e -> 'crit' ->> 'card_rolls')::int;
  elsif v_out = 'success' then
    v_gold := round(x.cargo_value * (1 + coalesce((fx ->> 'sales_gold')::numeric, 0)), 2);
  else
    v_loss := ((r -> 'loss' ->> 0)::double precision + public.rand01() * ((r -> 'loss' ->> 1)::double precision - (r -> 'loss' ->> 0)::double precision))
              * (1 + coalesce((lead ->> 'loss_pct')::double precision, 0) / 100);
    v_loss := greatest(0, least(1, v_loss)) * (1 - least(100, public.jnum(x.card_fx, 'loss_red')) / 100);  -- Estrada Livre
    -- o Cachorro pode farejar a carga perdida
    if public.rand01() < coalesce((fx ->> 'dog_recover')::double precision, 0) then v_rec := true; v_loss := 0; end if;
    for c in select key, value::int q from jsonb_each_text(x.cargo) loop
      v_lost := round(c.q * v_loss)::int;
      v_back := v_back || jsonb_build_object(c.key, c.q - v_lost);
    end loop;
    if x.insurance > 0 then
      v_refund := round(greatest(0, v_loss - (e ->> 'insurance_deductible')::double precision)::numeric * x.cargo_value, 2);
    end if;
  end if;

  if v_gold > 0 then v_gold := round(v_gold * (1 + public.jnum(x.card_fx, 'profit')::numeric / 100), 2); end if;  -- carta de Veículo
  if v_gold > 0 then v_gold := v_gold + public.moon_bonus(x.user_id, v_gold, fx); end if;
  -- missões: ouro ganho e viagem longe com sucesso
  perform public.mission_progress(x.user_id, 'gold_earned', v_gold);
  if v_out <> 'fail' and public.exp_route_idx(x.route_id) >= public.exp_route_idx(public.config_get('missions') ->> 'far_route') then
    perform public.mission_progress(x.user_id, 'exp_far_success', 1);
  end if;

  -- prêmio (v3): chance de carta (sorteada ao Receber); o crítico rola mais vezes; Gerente e Ferradura aumentam a chance
  for k in 1 .. v_rolls loop
    if public.rand01() < (r ->> 'card_chance')::double precision * (1 + coalesce((lead ->> 'item_pct')::double precision, 0) / 100) * (1 + public.jnum(x.card_fx, 'item_boost') / 100) then
      v_drops := v_drops || to_jsonb('card'::text);
    end if;
  end loop;

  v_txt := (e -> 'reports' -> v_out) ->> floor(public.rand01() * jsonb_array_length(e -> 'reports' -> v_out))::int;
  v_txt := replace(replace(v_txt, '{route}', r ->> 'name_pt'), '{lost}', round(coalesce(v_loss, 0) * 100)::text || '%');
  if v_rec then v_txt := v_txt || ' ' || (e -> 'reports' ->> 'recovered'); end if;

  update public.expeditions set status = 'back', outcome = v_out, loss_frac = v_loss, gold = v_gold, refund = v_refund,
      cargo_back = v_back, drops = v_drops, report = v_txt
    where id = p_id;
  update public.farms set exp_fail_streak = case when v_out = 'fail' then exp_fail_streak + 1 else 0 end where user_id = x.user_id;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (x.user_id, 'expedition.back', x.user_id, jsonb_build_object('id', x.id, 'route', x.route_id, 'vehicle', x.vehicle_id,
      'outcome', v_out, 'chance', round(x.chance::numeric, 4), 'roll', round(u::numeric, 6), 'gold', v_gold, 'refund', v_refund, 'drops', v_drops));
end;
$function$;
