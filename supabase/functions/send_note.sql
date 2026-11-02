-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.send_note(p_target uuid, p_emojis text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); n jsonb := public.config_get('social') -> 'notes'; d date;
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if p_target is null or p_target = v_user or not exists (select 1 from public.farms where user_id = p_target) then raise exception 'jogador não encontrado' using errcode = 'check_violation'; end if;
  if public.social_blocked(v_user, p_target) then raise exception 'jogador indisponível' using errcode = 'check_violation'; end if;
  if coalesce(cardinality(p_emojis), 0) < 1 or cardinality(p_emojis) > (n ->> 'max_emojis')::int
     or exists (select 1 from unnest(p_emojis) e where not (n -> 'emojis') ? e) then
    raise exception 'recado inválido' using errcode = 'check_violation';
  end if;
  d := public.user_day(v_user, now());
  perform 1 from public.farms where user_id = v_user for update;
  if (select count(*) from public.visit_notes where from_user = v_user and to_user = p_target and day = d) >= (n ->> 'per_target_per_day')::int then
    raise exception 'já deixou recado hoje' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.visit_notes where from_user = v_user and day = d) >= (n ->> 'per_day')::int then
    raise exception 'recados de hoje acabaram' using errcode = 'check_violation';
  end if;
  insert into public.visit_notes (from_user, to_user, emojis, day) values (v_user, p_target, p_emojis, d);
  return public.visit_view(v_user, p_target);
end;
$$;
