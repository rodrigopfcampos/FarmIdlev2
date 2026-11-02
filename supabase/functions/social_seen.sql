-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.social_seen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  update public.farms set social_seen_at = now() where user_id = v_user;
  return public.social_state(v_user);
end;
$$;
