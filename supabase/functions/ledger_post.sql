-- versão atual (veio de supabase/migrations/20261023000100_phase0_base.sql)
create or replace function public.ledger_post(
  p_user uuid, p_amount numeric, p_reason text, p_ref jsonb default '{}'::jsonb, p_idempotency_key text default null
) returns public.ledger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.ledger;
  v_gold numeric(18, 2);
begin
  if p_amount is null or p_amount = 0 then
    raise exception 'valor do lançamento não pode ser zero';
  end if;
  -- mesma chave de idempotência = mesmo lançamento, sem cobrar duas vezes
  if p_idempotency_key is not null then
    select * into v_row from public.ledger where user_id = p_user and idempotency_key = p_idempotency_key;
    if found then return v_row; end if;
  end if;
  -- trava a carteira contra gasto duplo
  select gold into v_gold from public.wallets where user_id = p_user for update;
  if not found then raise exception 'carteira não encontrada'; end if;
  if v_gold + p_amount < 0 then
    raise exception 'ouro insuficiente' using errcode = 'check_violation';
  end if;
  update public.wallets set gold = v_gold + p_amount, updated_at = now() where user_id = p_user;
  insert into public.ledger (user_id, amount, balance_after, reason, ref, idempotency_key)
    values (p_user, p_amount, v_gold + p_amount, p_reason, coalesce(p_ref, '{}'::jsonb), p_idempotency_key)
    returning * into v_row;
  return v_row;
end;
$$;
