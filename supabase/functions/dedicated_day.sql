-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.dedicated_day(p_level int)
returns double precision language sql stable set search_path = '' as $$
  with pts as (select (x ->> 0)::double precision lv, (x ->> 1)::double precision d, row_number() over () i
               from jsonb_array_elements(public.config_get('anticheat') -> 'rules' -> 'progress' -> 'dedicated_level_days') x),
  seg as (select a.lv l0, a.d d0, b.lv l1, b.d d1 from pts a join pts b on b.i = a.i + 1)
  select coalesce((select d0 + (p_level - l0) / nullif(l1 - l0, 0) * (d1 - d0) from seg where p_level between l0 and l1 limit 1), 0)
$$;
