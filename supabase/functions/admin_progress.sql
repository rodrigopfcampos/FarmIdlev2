-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_progress()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'level', f.level,
      'lots', (select count(*) from public.owned_lots l where l.user_id = p.id),
      'age_days', round((extract(epoch from (now() - p.created_at)) / 86400)::numeric, 1),
      'dedicated_day', round(public.dedicated_day(f.level)::numeric, 1),
      'fast', f.level >= 6 and extract(epoch from (now() - p.created_at)) / 86400 < public.dedicated_day(f.level) * 0.9) order by f.level desc), '[]')
    from public.profiles p join public.farms f on f.user_id = p.id);
end;
$$;
