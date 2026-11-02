-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_points(p_user uuid, p_value numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(p_value / nullif(public.ref_income(f.level) / 24, 0), 4) from public.farms f where f.user_id = p_user
$$;
