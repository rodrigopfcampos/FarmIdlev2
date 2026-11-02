-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.roll_rare_seed(p_user uuid, p_crop text, fx jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare odds jsonb := public.config_get('characters') -> 'field_effects' -> 'botanica' -> 'rare_seed_odds'; u double precision; acc double precision := 0; k text;
begin
  if coalesce((fx ->> 'rare_seed')::double precision, 0) <= 0 or public.rand01() >= (fx ->> 'rare_seed')::double precision then return; end if;
  u := public.rand01();
  for k in select x from unnest(array['uncommon', 'rare', 'legendary', 'mythic']) x loop
    acc := acc + coalesce((odds ->> k)::double precision, 0);
    if u < acc or k = 'mythic' then
      insert into public.inventory (user_id, item_id, qty) values (p_user, 'seed:' || p_crop || ':' || k, 1)
        on conflict (user_id, item_id) do update set qty = public.inventory.qty + 1;
      insert into public.audit_log (actor_id, action, target_user_id, data) values (null, 'seed.rare_drop', p_user, jsonb_build_object('crop', p_crop, 'rarity', k));
      return;
    end if;
  end loop;
end;
$$;
