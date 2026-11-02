-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.user_day(p_user uuid, p_at timestamptz default now())
returns date language sql stable security definer set search_path = '' as $$
  select (p_at at time zone coalesce(public.user_tz(p_user, p_at), 'America/Sao_Paulo'))::date
$$;
