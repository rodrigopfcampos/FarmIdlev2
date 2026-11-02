-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.draw_card(p_user uuid, p_origin text)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare
  g jsonb := public.config_get('cards') -> 'gacha'; f public.farms; u double precision; r text; acc double precision := 0; k text;
  floor_rank int := 1; tot double precision := 0; c jsonb; n int; v_serial bigint; v_state text := 'binder'; v_until timestamptz;
begin
  select * into f from public.farms where user_id = p_user for update;
  if f.pity_mythic + 1 >= (g -> 'pity_thresholds' ->> 'mythic')::int then floor_rank := 5;
  elsif f.pity_legendary + 1 >= (g -> 'pity_thresholds' ->> 'legendary_or_better')::int then floor_rank := 4;
  elsif f.pity_rare + 1 >= (g -> 'pity_thresholds' ->> 'rare_or_better')::int then floor_rank := 3; end if;
  -- chances da tabela, só com as raridades permitidas pela garantia (redistribuídas)
  for k in select key from jsonb_each_text(g -> 'base_rates') loop
    if public.rarity_rank(k) >= floor_rank then tot := tot + (g -> 'base_rates' ->> k)::double precision; end if;
  end loop;
  u := public.rand01() * tot;
  foreach k in array array['common', 'uncommon', 'rare', 'legendary', 'mythic'] loop
    if public.rarity_rank(k) >= floor_rank then
      acc := acc + (g -> 'base_rates' ->> k)::double precision; r := k;
      exit when u < acc;
    end if;
  end loop;
  c := public.config_get('cards') -> 'cards';
  n := jsonb_array_length(c);
  update public.farms set
      pity_rare = case when public.rarity_rank(r) >= 3 then 0 else pity_rare + 1 end,
      pity_legendary = case when public.rarity_rank(r) >= 4 then 0 else pity_legendary + 1 end,
      pity_mythic = case when r = 'mythic' then 0 else pity_mythic + 1 end
    where user_id = p_user;
  -- fichário cheio: a carta espera na caixa de entrada
  if (select count(*) from public.cards where user_id = p_user and state = 'binder') >= f.binder_slots then
    v_state := 'inbox';
    v_until := now() + make_interval(days => (public.config_get('cards') -> 'binder' ->> 'inbox_overflow_retention_days')::int);
  end if;
  insert into public.cards (user_id, card_id, rarity, state, origin, inbox_until)
    values (p_user, c -> floor(public.rand01() * n)::int ->> 'id', r, v_state, p_origin, v_until)
    returning serial into v_serial;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'card.drawn', p_user, jsonb_build_object('serial', v_serial, 'rarity', r, 'origin', p_origin, 'pity_floor', floor_rank, 'state', v_state));
  return v_serial;
end;
$$;
