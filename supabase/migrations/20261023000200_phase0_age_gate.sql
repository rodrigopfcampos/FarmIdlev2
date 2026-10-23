-- Público 18+ (seção 15 do GDD): o servidor recusa conta sem data de nascimento ou de menor de idade.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nick text := nullif(trim(new.raw_user_meta_data ->> 'nickname'), '');
  v_birth date;
  v_start numeric := coalesce((public.config_get('levels') ->> 'starting_gold')::numeric, 0);
begin
  begin
    v_birth := (new.raw_user_meta_data ->> 'birth_date')::date;
  exception when others then
    v_birth := null;
  end;
  if v_birth is null or v_birth > (current_date - interval '18 years')::date then
    raise exception 'conta exige 18 anos ou mais' using errcode = 'check_violation';
  end if;
  if v_nick is null or char_length(v_nick) not between 3 and 20 then
    v_nick := 'Fazendeiro' || substr(replace(new.id::text, '-', ''), 1, 6);
  end if;
  insert into public.profiles (id, nickname, birth_date) values (new.id, v_nick, v_birth);
  insert into public.wallets (user_id) values (new.id);
  if v_start > 0 then
    perform public.ledger_post(new.id, v_start, 'starting_gold', jsonb_build_object('config', 'levels'), 'starting_gold');
  end if;
  insert into public.audit_log (actor_id, action, target_user_id, data)
    values (null, 'account.created', new.id, jsonb_build_object('starting_gold', v_start));
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
