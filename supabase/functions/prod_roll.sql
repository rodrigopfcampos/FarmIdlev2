-- versão atual (veio de supabase/migrations/20261028000100_phase7_missions_cards.sql)
create or replace function public.prod_roll(p_user uuid, p_day date)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare f public.farms; w double precision := (public.config_get('missions') -> 'production_reference' ->> 'new_day_weight')::double precision;
begin
  select * into f from public.farms where user_id = p_user for update;
  if f.prod_day is not distinct from p_day then return; end if;
  if f.prod_day is not null and f.prod_day < p_day then
    update public.farms set
        prod_value_h = round((coalesce(prod_value_h, prod_day_value / 24) * (1 - w) + w * prod_day_value / 24)::numeric, 2),
        prod_xp_h = round((coalesce(prod_xp_h, prod_day_xp / 24) * (1 - w) + w * prod_day_xp / 24)::numeric, 2)
      where user_id = p_user;
  end if;
  update public.farms set prod_day = p_day, prod_day_value = 0, prod_day_xp = 0 where user_id = p_user;
end;
$$;
