-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.animals_feed_hungry(p_user uuid, p_t double precision, fx jsonb, p_gold numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare r record; v_total numeric := 0; v_c numeric;
begin
  for r in select house_id, slot from public.animals where user_id = p_user and state = 'hungry' order by house_id, slot loop
    v_c := public.animal_start(p_user, r.house_id, r.slot, p_t, fx, p_gold - v_total);
    exit when v_c is null;
    v_total := v_total + v_c;
  end loop;
  return v_total;
end;
$$;
