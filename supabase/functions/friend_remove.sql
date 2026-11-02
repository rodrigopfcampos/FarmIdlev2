-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.friend_remove(p_other uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  delete from public.friendships where user_a = least(v_user, p_other) and user_b = greatest(v_user, p_other);
  return public.social_state(v_user);
end;
$$;
