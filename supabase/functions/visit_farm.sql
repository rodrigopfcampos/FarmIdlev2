-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.visit_farm(p_target uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); r jsonb := public.config_get('social') -> 'random_visit'; t uuid := p_target;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if t is null then
    select f.user_id into t from public.farms f
      where f.user_id <> v_user and f.level >= (r ->> 'min_level')::int and f.last_activity_at > now() - make_interval(days => (r ->> 'active_days')::int)
        and not public.social_blocked(v_user, f.user_id)
      order by public.rand01() limit 1;
    if t is null then raise exception 'nenhuma fazenda para visitar agora' using errcode = 'check_violation'; end if;
  end if;
  if t = v_user or not exists (select 1 from public.farms where user_id = t) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, t) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  -- a fazenda do dono anda até agora (sem contar como atividade dele)
  perform public.advance_farm(t, now());
  return public.visit_view(v_user, t);
end;
$$;
