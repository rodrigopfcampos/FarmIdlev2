-- versão atual (nova)
create or replace function public.card_use(p_user uuid, p_kind text, p_units numeric)
returns void language plpgsql volatile security definer set search_path = '' as $$
-- uma coleta (ou partida de expedição) gasta usos das cartas em uso que melhoram essa atividade ("any" = qualquer coleta);
-- a carta que zera sai da mão no fim do passo (buffs_expire) e a coleta pode trazer uma carta nova (até o limite do dia)
declare at timestamptz := public.fx_at(); cfg jsonb := public.config_get('cards') -> 'rules'; d jsonb; v_day date; f public.farms; k int;
begin
  if coalesce(p_units, 0) <= 0 then return; end if;
  update public.card_buffs set uses_left = greatest(0, uses_left - p_units),
      ends_at = case when uses_left - p_units <= 0 then at else ends_at end
    where user_id = p_user and started_at <= at and ends_at > at
      and (public.card_def(card_id) -> 'uses_on') ?| array[p_kind, 'any'];
  -- carta nova da coleta (a expedição tem o achado dela)
  if p_kind = 'expedition' or current_setting('vif.missions', true) = 'off' then return; end if;
  d := cfg -> 'collect_drop';
  v_day := public.user_day(p_user, at);
  select * into f from public.farms where user_id = p_user for update;
  if f.collect_cards_day is distinct from v_day then
    update public.farms set collect_cards_day = v_day, collect_cards_n = 0 where user_id = p_user;
    f.collect_cards_n := 0;
  end if;
  if f.collect_cards_n >= (d ->> 'max_per_day')::int then return; end if;
  if public.rand01() < least(1, (d ->> 'chance_per_use')::double precision * p_units) then
    perform public.draw_card(p_user, 'collect');
    update public.farms set collect_cards_n = collect_cards_n + 1 where user_id = p_user;
  end if;
end;
$$;
