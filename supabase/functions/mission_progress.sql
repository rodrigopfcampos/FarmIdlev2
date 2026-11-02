-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.mission_progress(p_user uuid, p_metric text, p_amount numeric)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  at timestamptz := public.fx_at(); d date; w date; m public.missions; cfg jsonb := public.config_get('missions'); wk public.mission_weeks; n int;
begin
  if coalesce(p_amount, 0) <= 0 then return; end if;
  -- testes antigos (fases 0–6) desligam as missões para os prêmios não mudarem as contas deles
  if current_setting('vif.missions', true) = 'off' then return; end if;
  d := public.user_day(p_user, at); w := public.mission_week(d);
  perform public.mission_ensure(p_user, at);
  for m in update public.missions set progress = least(target, progress + p_amount),
               done_at = case when progress + p_amount >= target then at else null end
           where user_id = p_user and metric = p_metric and done_at is null
             and ((kind = 'daily' and period = d) or (kind = 'weekly' and period = w))
           returning * loop
    continue when m.done_at is null;
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'mission.done', p_user, jsonb_build_object('kind', m.kind, 'id', m.mission_id, 'period', m.period));
    if m.kind = 'daily' then
      if (m.reward ->> 'gold')::numeric > 0 then
        -- Comerciante (ramo Negócios): +5% por ponto no ouro das missões, com ele em campo
        perform public.ledger_post(p_user, round((m.reward ->> 'gold')::numeric * (1 + coalesce((select sum(public.skill_effect(ch.class_id, ch.skills, 'mission_gold_pct'))
            from public.characters ch where ch.user_id = p_user and public.char_active(ch)), 0)::numeric / 100), 2),
          'mission', jsonb_build_object('id', m.mission_id, 'period', m.period),
          'mission:' || m.kind || ':' || m.period || ':' || m.slot);
      end if;
      perform public.add_xp(p_user, (m.reward ->> 'xp')::numeric);
      -- as 5 do dia: 1 pacote (até o limite da semana); 2 cartas do nível 15 em diante
      if not exists (select 1 from public.missions where user_id = p_user and kind = 'daily' and period = d and done_at is null)
         and (select daily_pack_day from public.farms where user_id = p_user) is distinct from d then
        select * into wk from public.mission_weeks where user_id = p_user and week = w for update;
        if wk.daily_packs < (cfg -> 'daily' ->> 'max_packs_per_week')::int then
          update public.mission_weeks set daily_packs = daily_packs + 1 where user_id = p_user and week = w;
          update public.farms set daily_pack_day = d where user_id = p_user;
          for n in 1 .. public.daily_pack_cards(p_user) loop perform public.draw_card(p_user, 'daily_pack'); end loop;
        end if;
      end if;
    else
      select count(*) into n from public.missions where user_id = p_user and kind = 'weekly' and period = w and done_at is not null;
      select * into wk from public.mission_weeks where user_id = p_user and week = w for update;
      if n >= 3 and wk.weekly_rewards < 1 then
        update public.mission_weeks set weekly_rewards = 1 where user_id = p_user and week = w;
        perform public.draw_card(p_user, 'weekly_3');
      end if;
      if n >= (cfg -> 'weekly' ->> 'count')::int and wk.weekly_rewards < 2 then
        update public.mission_weeks set weekly_rewards = 2 where user_id = p_user and week = w;
        perform public.draw_card(p_user, 'weekly_5');
      end if;
    end if;
  end loop;
end;
$$;
