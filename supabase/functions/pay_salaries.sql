-- versão atual (veio de supabase/migrations/20261024000100_phase3_characters.sql)
create or replace function public.pay_salaries()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'precisa estar logado' using errcode = 'insufficient_privilege'; end if;
  perform public.touch_farm(v_user);
  if not exists (select 1 from public.characters where user_id = v_user and debt > 0) then
    raise exception 'nenhum salário atrasado' using errcode = 'check_violation';
  end if;
  if public.pay_debts(v_user) = 0 then raise exception 'ouro insuficiente' using errcode = 'check_violation'; end if;
  return public.farm_state(v_user);
end;
$$;
