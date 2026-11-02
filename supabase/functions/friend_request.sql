-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.friend_request(p_target uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); cfg jsonb := public.config_get('social') -> 'friends'; x public.friendships;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  select * into x from public.friendships where user_a = least(v_user, p_target) and user_b = greatest(v_user, p_target) for update;
  if found and x.status = 'accepted' then raise exception 'vocês já são amigos' using errcode = 'check_violation'; end if;
  if found and x.requested_by = v_user then raise exception 'pedido já enviado' using errcode = 'check_violation'; end if;
  if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'accepted') >= (cfg ->> 'max_friends')::int then
    raise exception 'limite de amigos' using errcode = 'check_violation';
  end if;
  if found then
    -- os dois pediram: vira amizade
    update public.friendships set status = 'accepted', accepted_at = now() where user_a = x.user_a and user_b = x.user_b;
  else
    if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'pending' and requested_by = v_user) >= (cfg ->> 'max_pending_out')::int then
      raise exception 'muitos pedidos esperando' using errcode = 'check_violation';
    end if;
    insert into public.friendships (user_a, user_b, requested_by) values (least(v_user, p_target), greatest(v_user, p_target), v_user);
  end if;
  return public.social_state(v_user);
end;
$$;
