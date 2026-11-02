-- versão atual (veio de supabase/migrations/20261108000100_v3_passive_tree.sql)
create or replace function public.tick_team(p_user uuid, p_hours double precision, p_frac double precision, fx jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := public.config_get('characters');
  dr jsonb := public.config_get('tools_and_items') -> 'tool_durability_rules';
  snacks jsonb := public.config_get('tools_and_items') -> 'snack_cards';
  c public.characters; en jsonb; v_e double precision; v_h double precision; v_lvl int; v_park boolean; v_qty int; v_rev date;
  v_today date := public.game_day(now()); s jsonb; worked double precision; v_snack_day date;
begin
  for c in select * from public.characters where user_id = p_user for update loop
    en := public.char_energy(c, fx);
    v_e := c.energy; v_h := c.work_hours; v_lvl := c.level; v_park := c.parked; v_qty := c.snack_qty; v_rev := c.revive_day; v_snack_day := c.snack_day;
    if c.leading_id is not null then
      null; -- conduzindo uma expedição: nem trabalha nem descansa
    elsif c.slot = 'field' and not c.parked and public.char_active(c) and c.energy > 0 then
      worked := p_hours * p_frac;
      v_e := v_e - (en ->> 'use')::double precision * worked;
      v_h := v_h + worked * (1 + coalesce((fx ->> 'char_xp')::double precision, 0)); -- neblina e cartas
      update public.tools set durability = greatest(0, durability - (dr ->> 'loss_per_work_hour')::double precision * worked * (1 - coalesce((fx ->> 'tool_wear_cut')::double precision, 0)))
        where user_id = p_user and class_id = c.class_id;
      if v_e <= 0 then
        v_e := 0;
        if greatest(public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'), coalesce((fx ->> 'revive_pct')::double precision, 0) * (en ->> 'max')::double precision) > 0
           and v_rev is distinct from v_today then
          -- Segundo Fôlego: volta com 30% da energia máxima, 1×/dia, sem ir ao banco
          v_e := greatest(public.skill_effect(c.class_id, c.skills, 'daily_revive_energy'), coalesce((fx ->> 'revive_pct')::double precision, 0) * (en ->> 'max')::double precision); v_rev := v_today;
        else
          v_park := true;
        end if;
      end if;
    else
      v_e := least((en ->> 'max')::double precision, v_e + (en ->> 'rest')::double precision * p_hours);
      if v_park and v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
    end if;
    -- lanche automático abaixo de 15% da energia máxima
    if v_qty > 0 and c.snack_id is not null then
      s := (select x from jsonb_array_elements(snacks) x where x ->> 'id' = c.snack_id);
      while v_qty > 0 and v_e < (s ->> 'auto_trigger_below_energy_pct')::double precision / 100 * (en ->> 'max')::double precision loop
        -- Café Forte: o 1º lanche do dia de cada personagem recupera mais
        v_e := least((en ->> 'max')::double precision, v_e + (s ->> 'energy_restore')::double precision * (1 + coalesce((fx ->> 'snack_boost')::double precision, 0)
               + case when v_snack_day is distinct from v_today then coalesce((fx ->> 'first_snack')::double precision, 0) else 0 end));
        v_snack_day := v_today;
        v_qty := v_qty - 1;
        if v_e >= (cfg -> 'energy' ->> 'parked_until')::double precision then v_park := false; end if;
      end loop;
    end if;
    -- nível do personagem: (10 + 1,5 × nível) horas para o próximo
    while v_lvl < (cfg -> 'character_level' ->> 'max')::int
      and v_h >= (cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl loop
      v_h := v_h - ((cfg -> 'character_level' ->> 'base_hours')::double precision + (cfg -> 'character_level' ->> 'per_level_hours')::double precision * v_lvl);
      v_lvl := v_lvl + 1;
    end loop;
    if v_lvl = (cfg -> 'character_level' ->> 'max')::int then v_h := 0; end if;
    if v_lvl > c.level then perform public.mission_progress(p_user, 'char_level', v_lvl - c.level); end if;
    update public.characters set energy = v_e, work_hours = v_h, level = v_lvl, parked = v_park, snack_qty = v_qty,
        snack_id = case when v_qty = 0 then null else snack_id end, revive_day = v_rev, snack_day = v_snack_day
      where user_id = p_user and class_id = c.class_id;
  end loop;
end;
$function$;
