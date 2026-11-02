-- versão atual (veio de supabase/migrations/20261029000100_phase8a_social.sql)
create or replace function public.search_players(p_query text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); s jsonb := public.config_get('social') -> 'search'; q text := trim(coalesce(p_query, ''));
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  if char_length(q) < (s ->> 'min_chars')::int then raise exception 'digite pelo menos 3 letras' using errcode = 'check_violation'; end if;
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  return (select coalesce(jsonb_agg(public.player_card(x.id) || jsonb_build_object('status', public.friend_status(v_user, x.id))), '[]')
    from (select p.id from public.profiles p join public.farms f on f.user_id = p.id
          where p.id <> v_user and p.nickname ilike q || '%' and not exists (select 1 from public.blocks b where b.user_id = p.id and b.blocked_id = v_user)
          order by lower(p.nickname) = lower(trim(p_query)) desc, p.nickname limit (s ->> 'max_results')::int) x);
end;
$$;
