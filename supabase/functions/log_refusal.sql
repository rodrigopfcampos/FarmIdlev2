-- versão atual (veio de supabase/migrations/20261031000100_phase9_admin.sql)
create or replace function public.log_refusal(p_fn text, p_msg text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;
  if (select count(*) from public.refusals where user_id = v_user and at > now() - interval '1 hour') >= 200 then return; end if;
  insert into public.refusals (user_id, fn, msg) values (v_user, left(coalesce(p_fn, ''), 60), left(coalesce(p_msg, ''), 200));
end;
$$;
