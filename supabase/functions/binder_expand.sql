-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.binder_expand()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); b jsonb := public.config_get('cards') -> 'binder'; f public.farms; v numeric;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  select * into f from public.farms where user_id = v_user for update;
  if f.binder_slots + (b ->> 'expansion_slots')::int > (b ->> 'max_slots')::int then raise exception 'fichário já está no máximo' using errcode = 'check_violation'; end if;
  v := round(public.ref_income(f.level) * (b ->> 'expansion_cost_reference_income_ratio')::numeric, 2);
  perform public.ledger_post(v_user, -v, 'binder_expand', jsonb_build_object('slots', f.binder_slots + (b ->> 'expansion_slots')::int));
  update public.farms set binder_slots = binder_slots + (b ->> 'expansion_slots')::int where user_id = v_user;
  perform public.cards_maintain(v_user);
  return public.farm_state(v_user);
end;
$$;
