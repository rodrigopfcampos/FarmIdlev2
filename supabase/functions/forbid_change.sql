-- versão atual (veio de supabase/migrations/20261023000100_phase0_base.sql)
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
