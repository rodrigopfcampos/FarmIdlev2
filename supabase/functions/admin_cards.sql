-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.admin_cards()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.admin_need('reader');
begin
  return jsonb_build_object(
    'by_rarity', (select coalesce(jsonb_agg(jsonb_build_object('rarity', rarity, 'n', n, 'share', round(n::numeric / nullif(t, 0), 4),
        'expected', (public.config_get('cards') -> 'gacha' -> 'effective_rates_with_pity' ->> rarity)::numeric)), '[]')
      from (select rarity, count(*) n, sum(count(*)) over () t from public.cards where origin not in ('admin') group by rarity) x),
    'by_origin', (select coalesce(jsonb_object_agg(origin, n), '{}') from (select origin, count(*) n from public.cards group by origin) y),
    'armory_complete', (select count(*) from (select user_id, card_id from public.armory group by 1, 2 having count(*) = 5) z),
    'sold_to_collector', (select count(*) from public.cards where state = 'sold'));
end;
$$;
