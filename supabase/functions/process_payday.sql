-- versão atual (veio de supabase/migrations/20261027000100_phase6_weather.sql)
create or replace function public.process_payday(p_user uuid, p_until timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_last date; v_today date := public.user_day(p_user, p_until); v_gold numeric; v_sal numeric; c public.characters;
begin
  select coalesce(last_payday, v_today) into v_last from public.farms where user_id = p_user for update;
  while v_last < v_today loop
    v_last := v_last + 1;
    for c in select * from public.characters where user_id = p_user and class_id <> 'agricultor' order by hired_at loop
      v_sal := public.salary_of(p_user, c);
      if v_sal <= 0 then continue; end if;
      select gold into v_gold from public.wallets where user_id = p_user;
      if c.debt = 0 and v_gold >= v_sal then
        perform public.ledger_post(p_user, -v_sal, 'salary', jsonb_build_object('class', c.class_id, 'day', v_last), 'salary:' || c.class_id || ':' || v_last);
      else
        update public.characters set debt = debt + v_sal, unpaid_days = unpaid_days + 1 where user_id = p_user and class_id = c.class_id;
      end if;
    end loop;
  end loop;
  update public.farms set last_payday = v_last where user_id = p_user;
end;
$function$;
