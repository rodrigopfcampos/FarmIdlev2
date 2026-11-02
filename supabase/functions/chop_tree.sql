-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
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
  update public.trees set fruit_id = null, planted_at = null, ready_at = null, rarity = null, rare_left = 0
    where user_id = v_user and lot_id = p_lot and slot = p_slot;
  if not found then raise exception 'vaga de árvore não encontrada' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;
