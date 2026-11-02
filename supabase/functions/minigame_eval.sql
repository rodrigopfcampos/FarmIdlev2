-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.minigame_eval(mg public.minigames, p_keys jsonb)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  m jsonb := public.config_get('expeditions') -> 'minigame'; n int := array_length(mg.arrows, 1);
  pos int := 0; errs int := 0; last_t double precision := 0; prev double precision; k record; iv double precision[] := '{}';
  fin double precision; real_ms double precision := extract(epoch from (now() - mg.started_at)) * 1000; res text; robot boolean := false;
begin
  for k in select x ->> 'k' key, (x ->> 't')::double precision t from jsonb_array_elements(coalesce(p_keys, '[]')) with ordinality a(x, o) order by o loop
    exit when pos >= n;
    if prev is not null then iv := iv || (k.t - prev); end if;
    prev := k.t;
    if k.key = mg.arrows[pos + 1] then pos := pos + 1; last_t := k.t; else errs := errs + 1; end if;
  end loop;
  if array_length(iv, 1) >= 1 and (select min(z) from unnest(iv) z) < (m ->> 'min_interval_ms')::double precision then robot := true; end if;
  if array_length(iv, 1) >= 3 and (select max(z) - min(z) from unnest(iv) z) < 5 then robot := true; end if;
  if pos = n then
    fin := greatest(last_t + errs * (m ->> 'wrong_key_penalty_s')::double precision * 1000, real_ms - (m ->> 'tolerance_ms')::double precision);
    if fin <= mg.limit_ms then
      res := case when errs = 0 and not mg.calm and fin <= mg.limit_ms * (1 - (m ->> 'perfect_time_left')::double precision) then 'perfect' else 'done' end;
    end if;
  end if;
  if res is null then
    res := case when pos >= n * (m ->> 'incomplete_min_fraction')::double precision then 'incomplete' else 'failed' end;
  end if;
  if robot and res = 'perfect' then res := 'done'; end if;
  return jsonb_build_object('result', res, 'robot', robot, 'errors', errs, 'done', pos, 'of', n, 'finish_ms', round(coalesce(fin, real_ms)));
end;
$$;
