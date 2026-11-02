-- versão atual (veio de supabase/migrations/20261107000100_v3_tools_by_level.sql)
create or replace function public.tools_autotier(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_tier text; v_idx int;
begin
  select public.tool_tier(level) into v_tier from public.farms where user_id = p_user;
  v_idx := public.material_idx(v_tier);
  update public.tools set material = v_tier where user_id = p_user and public.material_idx(material) < v_idx;
end;
$$;
