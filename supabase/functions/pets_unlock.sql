-- versão atual (veio de supabase/migrations/20261110000100_v3_pets_cards_drops.sql)
create or replace function public.pets_unlock(p_user uuid, p_time double precision)
returns void language plpgsql security definer set search_path = '' as $$
declare v_level int; x jsonb;
begin
  select level into v_level from public.farms where user_id = p_user;
  for x in select value from jsonb_array_elements(public.config_get('characters') -> 'pets' -> 'list') loop
    if (x ->> 'unlock_level')::int <= v_level then
      insert into public.pets (user_id, pet_id, active, find_t) values (p_user, x ->> 'id', true, p_time)
        on conflict (user_id, pet_id) do nothing;
    end if;
  end loop;
end;
$$;
