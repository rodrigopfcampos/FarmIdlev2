-- Fase 1: painel básico do admin (busca de jogador, ledger, auditoria e fazenda).
-- Só conta com is_admin = true E login com 2FA (aal2). Toda consulta do admin fica no audit_log.

create or replace function public.admin_guard()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null or not coalesce((select is_admin from public.profiles where id = v_user), false) then
    raise exception 'acesso só para admin' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'admin precisa entrar com 2FA' using errcode = 'insufficient_privilege';
  end if;
  return v_user;
end;
$$;

-- quem sou eu (não exige 2FA, para a tela saber se pede o código)
create or replace function public.admin_whoami()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'is_admin', coalesce((select is_admin from public.profiles where id = auth.uid()), false),
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'))
$$;

create or replace function public.admin_search_players(p_query text)
returns table (user_id uuid, nickname text, email text, gold numeric, created_at timestamptz, last_activity_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  insert into public.audit_log (actor_id, action, data) values (v_admin, 'admin.search', jsonb_build_object('query', left(p_query, 100)));
  return query
    select p.id, p.nickname, u.email::text, w.gold, p.created_at, f.last_activity_at
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.wallets w on w.user_id = p.id
    left join public.farms f on f.user_id = p.id
    where coalesce(p_query, '') = '' or p.nickname ilike '%' || p_query || '%' or u.email ilike '%' || p_query || '%' or p.id::text = p_query
    order by p.created_at desc
    limit 50;
end;
$$;

create or replace function public.admin_player_ledger(p_user uuid, p_limit int default 100)
returns setof public.ledger
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_ledger', p_user);
  return query select * from public.ledger where user_id = p_user order by id desc limit least(greatest(p_limit, 1), 500);
end;
$$;

create or replace function public.admin_player_audit(p_user uuid, p_limit int default 100)
returns setof public.audit_log
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_audit', p_user);
  return query select * from public.audit_log where target_user_id = p_user or actor_id = p_user order by id desc limit least(greatest(p_limit, 1), 500);
end;
$$;

-- fazenda do jogador como ele veria agora (sem avançar nem marcar atividade)
create or replace function public.admin_player_farm(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid := public.admin_guard();
begin
  insert into public.audit_log (actor_id, action, target_user_id) values (v_admin, 'admin.view_farm', p_user);
  return public.farm_state(p_user);
end;
$$;

revoke all on function public.admin_guard() from public, anon, authenticated;
revoke all on function public.admin_whoami() from public, anon;
revoke all on function public.admin_search_players(text) from public, anon;
revoke all on function public.admin_player_ledger(uuid, int) from public, anon;
revoke all on function public.admin_player_audit(uuid, int) from public, anon;
revoke all on function public.admin_player_farm(uuid) from public, anon;
grant execute on function public.admin_whoami() to authenticated;
grant execute on function public.admin_search_players(text) to authenticated;
grant execute on function public.admin_player_ledger(uuid, int) to authenticated;
grant execute on function public.admin_player_audit(uuid, int) to authenticated;
grant execute on function public.admin_player_farm(uuid) to authenticated;
