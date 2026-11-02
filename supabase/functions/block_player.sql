-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.block_player(p_target uuid, p_block boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if p_block then
    insert into public.blocks (user_id, blocked_id) values (v_user, p_target) on conflict do nothing;
    delete from public.friendships where user_a = least(v_user, p_target) and user_b = greatest(v_user, p_target);
  else
    delete from public.blocks where user_id = v_user and blocked_id = p_target;
  end if;
  insert into public.audit_log (actor_id, action, target_user_id, data) values (v_user, case when p_block then 'social.block' else 'social.unblock' end, p_target, '{}');
  return public.social_state(v_user);
end;
$$;
