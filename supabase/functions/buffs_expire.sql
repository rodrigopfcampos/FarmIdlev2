-- versão atual (veio de supabase/migrations/20261102000100_v3_cards.sql)
create or replace function public.buffs_expire(p_user uuid, p_at timestamptz)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare b public.card_buffs;
begin
  for b in select * from public.card_buffs where user_id = p_user and ends_at <= p_at for update loop
    perform public.card_leave_hand(p_user, b, b.ends_at);
  end loop;
end;
$$;
