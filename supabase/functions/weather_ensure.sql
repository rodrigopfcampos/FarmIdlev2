-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.weather_ensure(p_user uuid, p_from timestamptz, p_to timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare tz text; d date; d1 date; f timestamptz := greatest(p_from, p_to - interval '2 days');
begin
  for tz in select distinct x from unnest(array[public.user_tz(p_user, f), public.user_tz(p_user, p_to + interval '1 day')]) x where x is not null loop
    d := (f at time zone tz)::date - 1; d1 := (p_to at time zone tz)::date + 1;
    while d <= d1 loop perform public.weather_day_ensure(public.tz_offset_min(tz, d), d); d := d + 1; end loop;
  end loop;
end;
$$;
