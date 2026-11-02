-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.friend_respond(p_other uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); x public.friendships;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  select * into x from public.friendships where user_a = least(v_user, p_other) and user_b = greatest(v_user, p_other) and status = 'pending' and requested_by = p_other for update;
  if not found then raise exception 'pedido não encontrado' using errcode = 'check_violation'; end if;
  if p_accept then
    if (select count(*) from public.friendships where (user_a = v_user or user_b = v_user) and status = 'accepted') >= (public.config_get('social') -> 'friends' ->> 'max_friends')::int then
      raise exception 'limite de amigos' using errcode = 'check_violation';
    end if;
    update public.friendships set status = 'accepted', accepted_at = now() where user_a = x.user_a and user_b = x.user_b;
  else
    delete from public.friendships where user_a = x.user_a and user_b = x.user_b;
  end if;
  return public.social_state(v_user);
end;
$$;
