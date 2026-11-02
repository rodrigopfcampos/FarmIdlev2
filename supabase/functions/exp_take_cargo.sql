-- versão atual (veio de supabase/migrations/20261026000100_phase5_expeditions.sql)
create or replace function public.exp_take_cargo(p_user uuid, p_cargo jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare c record;
begin
  for c in select key, value::int q from jsonb_each_text(p_cargo) loop
    if c.q <= 0 then raise exception 'quantidade inválida' using errcode = 'check_violation'; end if;
    if public.item_price(c.key) is null then raise exception 'item sem preço' using errcode = 'check_violation'; end if;
    update public.silo set qty = qty - c.q where user_id = p_user and item_id = c.key and qty >= c.q;
    if not found then raise exception 'quantidade maior que o Silo' using errcode = 'check_violation'; end if;
  end loop;
end;
$$;
