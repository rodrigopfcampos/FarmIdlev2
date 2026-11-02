-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.social_blocked(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.blocks where (user_id = p_a and blocked_id = p_b) or (user_id = p_b and blocked_id = p_a))
$$;
