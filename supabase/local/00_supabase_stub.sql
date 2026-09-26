-- Imitação mínima do que o Supabase já traz, para rodar migrações e testes num Postgres puro.
-- NÃO é migração: nunca aplicar no Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;
create schema if not exists extensions;
create table if not exists auth.users (id uuid primary key, email text);

-- Mesma semântica do Supabase: as claims do JWT vêm em request.jwt.claims.
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;
