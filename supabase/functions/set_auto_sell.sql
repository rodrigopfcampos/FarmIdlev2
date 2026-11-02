-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.set_auto_sell(p_item text, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if public.item_price(p_item) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
  perform public.touch_farm(v_user);
  insert into public.silo (user_id, item_id, qty, auto_sell) values (v_user, p_item, 0, coalesce(p_on, false))
    on conflict (user_id, item_id) do update set auto_sell = coalesce(p_on, false);
  return public.farm_state(v_user);
end;
$$;
