-- versão atual (veio de supabase/migrations/20261103000100_v3_card_supply.sql)
create or replace function public.add_xp(p_user uuid, p_xp numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_levels jsonb := public.config_get('levels') -> 'levels';
  v_level int; v_xp numeric; v_need numeric; v_start int; v_per numeric; v_stars int := 0;
begin
  select level, xp into v_level, v_xp from public.farms where user_id = p_user for update;
  v_start := v_level;
  v_xp := v_xp + p_xp;
  loop
    exit when v_level >= 50;
    v_need := (v_levels -> (v_level - 1) ->> 'xp_to_next')::numeric;
    exit when v_need is null or v_xp < v_need;
    v_xp := v_xp - v_need;
    v_level := v_level + 1;
  end loop;
  if v_level >= (public.config_get('village') -> 'stars' ->> 'unlock_level')::int then
    v_per := (v_levels -> 48 ->> 'xp_to_next')::numeric * (public.config_get('village') -> 'stars' ->> 'xp_per_star_ratio_of_level_49')::numeric;
    if v_per > 0 and v_xp >= v_per then
      v_stars := floor(v_xp / v_per)::int;
      v_xp := v_xp - v_stars * v_per;
    end if;
    v_xp := greatest(v_xp, 0);
  end if;
  update public.farms set level = v_level, xp = round(v_xp, 2), stars = stars + v_stars where user_id = p_user;
  if v_level > v_start then
    perform public.cards_level_up(p_user, v_level);
    insert into public.audit_log (actor_id, action, target_user_id, data)
      values (null, 'level.up', p_user, jsonb_build_object('from', v_start, 'to', v_level));
  end if;
end;
$$;
