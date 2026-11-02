-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.fish_collect(p_user uuid, p_t double precision, fx jsonb, p_team boolean)
returns int language plpgsql security definer set search_path = '' as $$
declare v_leg boolean := false; c jsonb := public.config_get('fishing'); f public.farms; n int; sp jsonb; v_val double precision; v_qty int; v_xp numeric; v_cyc double precision;
begin
  select * into f from public.farms where user_id = p_user for update;
  n := public.fish_cycles(p_user, p_t);
  if n < 1 then return 0; end if;
  v_cyc := (c ->> 'cycle_minutes')::double precision * 60;
  sp := public.fish_species(f.level);
  -- valor: 8% da renda do nível por dia ÷ 12 ciclos, × ciclos, × Vara de Pescar; a equipe rende 60%
  v_val := public.ref_income(f.level)::double precision * (c ->> 'value_share_of_R')::double precision / (c ->> 'cycles_per_day_reference')::double precision
         * n * (1 + coalesce((fx ->> 'fishing')::double precision, 0))
         * case when f.rod_durability < (c -> 'rod' ->> 'low_threshold')::double precision then (c -> 'rod' ->> 'low_multiplier')::double precision else 1 end
         * case when p_team then (c -> 'team' ->> 'efficiency')::double precision else 1 end;
  -- Mestre Pescador: peixe Lendário vale o dobro
  if public.rand01() < coalesce((fx ->> 'legendary_fish')::double precision, 0) then v_val := v_val * 2; v_leg := true; end if;
  v_qty := greatest(1, public.round_rand(v_val / (sp ->> 'fair_price_per_unit')::double precision));
  insert into public.silo (user_id, item_id, qty) values (p_user, sp ->> 'id', v_qty)
    on conflict (user_id, item_id) do update set qty = public.silo.qty + excluded.qty;
  v_xp := round((public.config_get('levels') -> 'levels' -> (greatest(1, least(49, f.level)) - 1) ->> 'xp_to_next')::numeric
               * (c ->> 'xp_per_cycle_ratio_of_level')::numeric * n, 2);
  perform public.produced(p_user, sp ->> 'id', v_qty, v_xp, 'fish');
  perform public.add_xp(p_user, round(v_xp * (1 + coalesce((fx ->> 'account_xp')::numeric, 0)), 2));
  update public.farms set fish_t = case when n >= (c ->> 'max_cycles')::int then p_t else fish_t + n * v_cyc end,
      rod_durability = greatest(0, rod_durability - (c -> 'rod' ->> 'wear_per_cycle')::double precision * n * (1 - coalesce((fx ->> 'tool_wear_cut')::double precision, 0)))
    where user_id = p_user;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'fish.collect', p_user, jsonb_build_object('cycles', n, 'fish', sp ->> 'id', 'qty', v_qty, 'team', p_team, 'legendary', v_leg));
  return v_qty;
end;
$$;
