-- versão atual (veio de supabase/migrations/20261104000100_v3_hand_use.sql)
create or replace function public.cards_starter(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare s jsonb := public.config_get('cards') -> 'rules' -> 'supply'; f public.farms; k text; v_serial bigint; v_r text;
begin
  -- testes antigos (fases 0–6) desligam as missões e as cartas de presente junto
  if current_setting('vif.missions', true) = 'off' then return; end if;
  select * into f from public.farms where user_id = p_user for update;
  if not found or f.starter_cards_at is not null then return; end if;
  update public.farms set starter_cards_at = now() where user_id = p_user;
  v_r := s ->> 'starter_rarity';
  for k in select jsonb_array_elements_text(s -> 'starter_cards') loop
    -- na mão, parada: o jogador escolhe quando usar
    if coalesce((s ->> 'starter_to_hand')::boolean, false)
       and not exists (select 1 from public.cards where user_id = p_user and card_id = k and state in ('hand', 'equipped'))
       and public.hand_count(p_user) < public.hand_slots(f.level) then
      insert into public.cards (user_id, card_id, rarity, state, origin, seen)
        values (p_user, k, v_r, 'hand', 'starter', true) returning serial into v_serial;
    else
      insert into public.cards (user_id, card_id, rarity, state, origin) values (p_user, k, v_r, 'binder', 'starter') returning serial into v_serial;
    end if;
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'card.starter', p_user, jsonb_build_object('serial', v_serial, 'card', k, 'rarity', v_r));
  end loop;
end;
$$;
