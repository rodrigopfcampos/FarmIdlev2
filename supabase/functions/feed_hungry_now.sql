-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.feed_hungry_now(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_time double precision; v_gold numeric; v_c numeric;
begin
  if not exists (select 1 from public.animals where user_id = p_user and state = 'hungry') then return; end if;
  select farm_time into v_time from public.farms where user_id = p_user;
  select gold into v_gold from public.wallets where user_id = p_user;
  v_c := public.animals_feed_hungry(p_user, v_time, public.team_fx(p_user), v_gold);
  if v_c > 0 then perform public.ledger_post(p_user, -round(v_c, 2), 'feed', jsonb_build_object('restart', true)); end if;
end;
$$;
