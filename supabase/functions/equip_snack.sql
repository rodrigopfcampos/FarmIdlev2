-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.equip_snack(p_class text, p_snack text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid(); c public.characters; v_have int; v_max int := 5; v_put int;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into c from public.characters where user_id = v_user and class_id = p_class for update;
  if not found then raise exception 'personagem não contratado' using errcode = 'check_violation'; end if;
  -- devolve o que estava no espaço
  if c.snack_id is not null and c.snack_qty > 0 and (p_snack is null or p_snack <> c.snack_id) then
    insert into public.inventory (user_id, item_id, qty) values (v_user, c.snack_id, c.snack_qty)
      on conflict (user_id, item_id) do update set qty = public.inventory.qty + excluded.qty;
    update public.characters set snack_id = null, snack_qty = 0 where user_id = v_user and class_id = p_class;
    c.snack_qty := 0;
  end if;
  if p_snack is not null then
    v_max := coalesce((select (x ->> 'max_stack_in_slot')::int from jsonb_array_elements(public.config_get('tools_and_items') -> 'snack_cards') x where x ->> 'id' = p_snack), 0);
    if v_max = 0 then raise exception 'lanche não existe' using errcode = 'check_violation'; end if;
    select qty into v_have from public.inventory where user_id = v_user and item_id = p_snack for update;
    v_put := least(coalesce(v_have, 0), v_max - case when c.snack_id = p_snack then c.snack_qty else 0 end);
    if v_put <= 0 then raise exception 'sem lanche no inventário' using errcode = 'check_violation'; end if;
    update public.inventory set qty = qty - v_put where user_id = v_user and item_id = p_snack;
    update public.characters set snack_id = p_snack, snack_qty = snack_qty + v_put where user_id = v_user and class_id = p_class;
  end if;
  return public.farm_state(v_user);
end;
$$;
