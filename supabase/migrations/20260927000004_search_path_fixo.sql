-- Security advisor (lint 0011): toda função dos schemas da aplicação com search_path fixo,
-- não só as SECURITY DEFINER. E a função auxiliar que o Supabase cria no public não fica exposta.

alter function fin.role_requires_mfa(text)       set search_path = fin, pg_temp;
alter function fin.assert_entry_balanced(uuid)   set search_path = fin, pg_temp;
alter function fin.trg_posting_balanced()        set search_path = fin, pg_temp;
alter function fin.trg_entry_has_postings()      set search_path = fin, pg_temp;
alter function fin.forbid_mutation()             set search_path = fin, pg_temp;
alter function fin.trg_account_guard()           set search_path = fin, pg_temp;
alter function fin.trg_period_open()             set search_path = fin, pg_temp;
alter function fin.trg_signer_designated()       set search_path = fin, pg_temp;
alter function audit.forbid_mutation()           set search_path = audit, pg_temp;

-- public.rls_auto_enable() é criada pelo Supabase (event trigger que liga RLS em tabela nova).
-- O event trigger roda como dono; ninguém precisa chamá-la pela API.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'rls_auto_enable') then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end $$;
