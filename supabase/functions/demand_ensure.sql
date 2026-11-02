-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.demand_ensure(p_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r jsonb; n int := coalesce((public.config_get('expeditions') -> 'daily_demand' ->> 'products')::int, 3);
begin
  if exists (select 1 from public.daily_demand where day = p_day) then return; end if;
  for r in select x from jsonb_array_elements(public.config_get('expeditions') -> 'routes') x loop
    insert into public.daily_demand (day, route_id, products)
    select p_day, r ->> 'id', array(
      select id from (
        select x ->> 'id' id from jsonb_array_elements(public.config_get('crops') -> 'crops') x
        union select x -> 'product' ->> 'id' from jsonb_array_elements(public.config_get('animals') -> 'animals') x) p
      order by public.rand01() limit n)
    on conflict do nothing;
  end loop;
end;
$$;
