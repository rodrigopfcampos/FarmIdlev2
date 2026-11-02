-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_title(p_user uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare o public.village_orders; r jsonb; t jsonb := public.config_get('village') -> 'encomenda' -> 'titles';
begin
  select * into o from public.village_orders where ends_at <= now() order by ends_at desc limit 1;
  if not found then return null; end if;
  r := public.village_result(o.id, p_user);
  if not (r ->> 'qualified')::boolean then return null; end if;
  if (r ->> 'top')::boolean then return t ->> 'top'; end if;
  if (r ->> 'goal_reached')::boolean then return t ->> 'participant'; end if;
  return null;
end;
$$;
