-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.weather_gen_blocks()
returns text[] language plpgsql volatile security definer set search_path = '' as $$
declare
  w jsonb := public.config_get('weather'); bh int := (w ->> 'block_hours')::int; n int := 24 / bh;
  out text[] := '{}'; b int; tot double precision; u double precision; acc double precision; k record; lim jsonb; pick text;
begin
  for b in 0 .. n - 1 loop
    -- tipos que podem cair neste bloco (Sol forte 09–18, Neblina 03–12); as chances dos outros são redistribuídas
    tot := 0;
    for k in select key, value::double precision v from jsonb_each_text(w -> 'chances') loop
      lim := w -> 'limits' -> k.key;
      if lim is null or (b * bh * 60 >= public.hm_min(lim ->> 0) and (b + 1) * bh * 60 <= public.hm_min(lim ->> 1)) then tot := tot + k.v; end if;
    end loop;
    u := public.rand01() * tot; acc := 0; pick := null;
    for k in select key, value::double precision v from jsonb_each_text(w -> 'chances') order by key loop
      lim := w -> 'limits' -> k.key;
      if lim is null or (b * bh * 60 >= public.hm_min(lim ->> 0) and (b + 1) * bh * 60 <= public.hm_min(lim ->> 1)) then
        acc := acc + k.v; pick := k.key;
        exit when u < acc;
      end if;
    end loop;
    out := out || pick;
  end loop;
  return out;
end;
$$;
