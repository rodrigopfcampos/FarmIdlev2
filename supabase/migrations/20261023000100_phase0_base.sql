-- Fase 0: perfis, carteira, ledger (livro-caixa imutável), audit_log e config do jogo.
-- Regras: o cliente só lê os próprios dados; toda escrita passa por funções do servidor;
-- ledger e audit_log nunca são alterados nem apagados.

-- ---------- config do jogo (cópia versionada de config/*.json) ----------
create table public.game_config (
  name text not null,
  version integer not null,
  data jsonb not null,
  created_at timestamptz not null default now(),
  primary key (name, version)
);
comment on table public.game_config is 'Cópia versionada de config/*.json; o servidor lê sempre a versão mais alta de cada nome.';

create or replace function public.config_get(p_name text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select data from public.game_config where name = p_name order by version desc limit 1
$$;

-- ---------- perfis ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  nickname text not null check (char_length(nickname) between 3 and 20),
  birth_date date,
  timezone text not null default 'America/Sao_Paulo',
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- carteira (saldo atual; só muda junto com o ledger) ----------
create table public.wallets (
  user_id uuid primary key references public.profiles (id) on delete restrict,
  gold numeric(18, 2) not null default 0 check (gold >= 0),
  updated_at timestamptz not null default now()
);

-- ---------- ledger: cada entrada e saída de ouro, para sempre ----------
create table public.ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete restrict,
  currency text not null default 'gold' check (currency = 'gold'),
  amount numeric(18, 2) not null check (amount <> 0),
  balance_after numeric(18, 2) not null check (balance_after >= 0),
  reason text not null check (reason ~ '^[a-z_]+$'),
  ref jsonb not null default '{}'::jsonb,
  idempotency_key text,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);
create index ledger_user_id_idx on public.ledger (user_id, id desc);

-- ---------- audit_log: ações importantes de jogadores, sistema e admins ----------
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,            -- null = sistema
  action text not null check (action ~ '^[a-z_.]+$'),
  target_user_id uuid,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_target_idx on public.audit_log (target_user_id, id desc);

-- ---------- imutabilidade: nada de update/delete/truncate ----------
create or replace function public.forbid_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% é somente inclusão: % não é permitido', tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
end;
$$;

create trigger ledger_no_update before update or delete on public.ledger
  for each row execute function public.forbid_change();
create trigger ledger_no_truncate before truncate on public.ledger
  for each statement execute function public.forbid_change();
create trigger audit_log_no_update before update or delete on public.audit_log
  for each row execute function public.forbid_change();
create trigger audit_log_no_truncate before truncate on public.audit_log
  for each statement execute function public.forbid_change();

-- ---------- lançamento no ledger (uso interno do servidor) ----------
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

-- ---------- conta nova: perfil, carteira e ouro inicial ----------
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

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- permissões ----------
alter table public.game_config enable row level security;
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.ledger enable row level security;
alter table public.audit_log enable row level security;

-- leitura: config é pública; cada jogador vê só o que é dele; audit_log só o servidor
create policy game_config_read on public.game_config for select to anon, authenticated using (true);
create policy profiles_read_own on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy wallets_read_own on public.wallets for select to authenticated using (user_id = (select auth.uid()));
create policy ledger_read_own on public.ledger for select to authenticated using (user_id = (select auth.uid()));

-- escrita direta proibida para o cliente (além do RLS, tira o privilégio)
revoke insert, update, delete, truncate on public.game_config, public.profiles, public.wallets, public.ledger, public.audit_log
  from anon, authenticated;
revoke all on public.audit_log from anon, authenticated;
revoke all on function public.ledger_post(uuid, numeric, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.forbid_change() from public, anon, authenticated;
