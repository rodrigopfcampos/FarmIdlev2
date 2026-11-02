-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.like_farm(p_target uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  d := public.user_day(v_user, now());
  insert into public.farm_likes (liker, target, day) values (v_user, p_target, d) on conflict do nothing;
  if not found then raise exception 'já curtiu hoje' using errcode = 'check_violation'; end if;
  update public.farms set likes_total = likes_total + 1 where user_id = p_target;
  return public.visit_view(v_user, p_target);
end;
$$;
