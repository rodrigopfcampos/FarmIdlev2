-- versão atual (veio de supabase/migrations/20261025000100_phase4_animals.sql)
create or replace function public.animal_start(p_user uuid, p_house text, p_slot int, p_t double precision, fx jsonb, p_gold_left numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare a public.animals; d jsonb; v_cost numeric;
begin
  select * into a from public.animals where user_id = p_user and house_id = p_house and slot = p_slot for update;
  if not found then return null; end if;
  d := public.animal_def(a.animal_id);
  v_cost := round((d ->> 'feed_cost_per_day')::numeric * (d ->> 'produce_every_minutes')::numeric / 1440
                  * (1 - coalesce((fx ->> 'feed_discount')::numeric, 0)), 2);
  if coalesce(p_gold_left, 0) < v_cost then
    update public.animals set state = 'hungry', cycle_start = p_t, ready_at = null where user_id = p_user and house_id = p_house and slot = p_slot;
    return null;
  end if;
  update public.animals set state = 'growing', cycle_start = p_t, ready_at = p_t + (d ->> 'produce_every_minutes')::double precision * 60
    where user_id = p_user and house_id = p_house and slot = p_slot;
  return v_cost;
end;
$$;
