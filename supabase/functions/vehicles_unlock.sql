-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.vehicles_unlock(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_level int;
begin
  select level into v_level from public.farms where user_id = p_user;
  insert into public.vehicles (user_id, vehicle_id, active)
    select p_user, x ->> 'id', false from jsonb_array_elements(public.config_get('expeditions') -> 'vehicles') x
    where (x ->> 'unlock_level')::int <= coalesce(v_level, 1)
    on conflict do nothing;
end;
$$;
