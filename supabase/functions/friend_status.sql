-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.friend_status(p_me uuid, p_other uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select case when f.status = 'accepted' then 'friend' when f.requested_by = p_me then 'sent' else 'received' end
                   from public.friendships f where f.user_a = least(p_me, p_other) and f.user_b = greatest(p_me, p_other)),
                  case when exists (select 1 from public.blocks where user_id = p_me and blocked_id = p_other) then 'blocked' else 'none' end)
$$;
