-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'level', f.level, 'likes', f.likes_total, 'title', public.village_title(p.id))
  from public.profiles p join public.farms f on f.user_id = p.id where p.id = p_user
$$;
