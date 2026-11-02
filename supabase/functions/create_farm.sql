-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.create_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_farm jsonb := public.config_get('farm');
  v_crops jsonb := public.config_get('crops');
  v_lot text := coalesce(v_farm ->> 'starting_lot', 'A1');
  v_rate double precision := (v_crops -> 'rules' -> 'work_units' ->> 'per_character_per_hour')::double precision;
  k int;
begin
  insert into public.farms (user_id, labor_bank, last_payday)
    values (p_user, coalesce(v_rate, 0) * coalesce((v_farm ->> 'initial_labor_bank_hours')::double precision, 0), public.game_day(now()))
    on conflict do nothing;
  insert into public.owned_lots (user_id, lot_id) values (p_user, v_lot) on conflict do nothing;
  for k in 1 .. coalesce((v_farm ->> 'plots_per_crop_lot')::int, 8) loop
    insert into public.plots (user_id, plot_id) values (p_user, v_lot || '-' || k) on conflict do nothing;
  end loop;
  insert into public.tools (user_id, class_id) values (p_user, 'agricultor') on conflict do nothing;
  insert into public.characters (user_id, class_id) values (p_user, 'agricultor') on conflict do nothing;
  insert into public.vehicles (user_id, vehicle_id, active)
    select p_user, x ->> 'id', true from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x
    where (x ->> 'cost')::numeric = 0 limit 1
    on conflict do nothing;
end;
$$;
