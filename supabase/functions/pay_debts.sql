-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.pay_debts(p_user uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare c public.characters; v_gold numeric; n int := 0;
begin
  for c in select * from public.characters where user_id = p_user and debt > 0 order by hired_at for update loop
    select gold into v_gold from public.wallets where user_id = p_user;
    exit when v_gold < c.debt;
    perform public.ledger_post(p_user, -c.debt, 'salary_debt', jsonb_build_object('class', c.class_id, 'days', c.unpaid_days));
    update public.characters set debt = 0, unpaid_days = 0 where user_id = p_user and class_id = c.class_id;
    n := n + 1;
  end loop;
  return n;
end;
$$;
