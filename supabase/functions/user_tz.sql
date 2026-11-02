-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.user_tz(p_user uuid, p_at timestamptz default now())
returns text language sql stable security definer set search_path = '' as $$
  select case when pr.tz_pending is not null and p_at >= pr.tz_pending_at then pr.tz_pending else pr.timezone end
  from public.profiles pr where pr.id = p_user
$$;
