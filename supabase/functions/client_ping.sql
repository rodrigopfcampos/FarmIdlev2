-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.client_ping(p_client_ms bigint, p_tz text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_skew double precision; c jsonb := public.config_get('anticheat') -> 'rules';
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  v_skew := abs(extract(epoch from now()) * 1000 - p_client_ms) / 60000;
  if v_skew > (c -> 'clock' ->> 'max_skew_minutes')::double precision then
    perform public.raise_alert(v_user, 'clock', jsonb_build_object('skew_min', round(v_skew::numeric, 1)));
  end if;
  update public.profiles set tz_mismatch_since = case
      when p_tz is null or p_tz = timezone then null
      else coalesce(tz_mismatch_since, now()) end
    where id = v_user;
  return jsonb_build_object('ok', true);
end;
$$;
