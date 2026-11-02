-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.touch_farm(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_block text := public.account_block_reason(p_user);
begin
  if v_block is not null then raise exception '%', v_block using errcode = 'insufficient_privilege'; end if;
  perform public.advance_farm(p_user, now());
  update public.farms set last_activity_at = now() where user_id = p_user;
  insert into public.farm_days (user_id, day, actions) values (p_user, (now() at time zone 'UTC')::date, 1)
    on conflict (user_id, day) do update set actions = public.farm_days.actions + 1;
  -- a sincronização automática do jogo não conta como clique
  if coalesce(current_setting('vif.sync', true), '') <> '1' then
    insert into public.action_times (user_id) values (p_user);
  end if;
  perform public.village_settle(p_user);
  perform public.anticheat_check(p_user);
end;
$$;
