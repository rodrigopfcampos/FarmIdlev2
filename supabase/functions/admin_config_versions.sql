-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_config_versions(p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'version', version, 'md5', md5(data::text), 'source', data ->> 'source', 'created_at', created_at) order by name, version desc), '[]')
    from public.game_config where p_name is null or name = p_name);
end;
$$;
