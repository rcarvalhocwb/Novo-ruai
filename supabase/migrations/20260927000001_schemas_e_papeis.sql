-- Fundação (F-04, F-05): schemas, extensões e papéis da aplicação.
-- Só o schema "api" é exposto no PostgREST (Settings > API > Exposed schemas: api).

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists api;
create schema if not exists fin;
create schema if not exists sales;
create schema if not exists integ;
create schema if not exists recon;
create schema if not exists access;
create schema if not exists audit;

-- Nada é público por padrão.
revoke all on schema fin, sales, integ, recon, access, audit from public, anon, authenticated;
revoke create on schema api from public, anon, authenticated;
grant usage on schema api to authenticated;

-- Funções nascem executáveis por PUBLIC no Postgres. Não se usa ALTER DEFAULT PRIVILEGES global
-- (atingiria extensões como pgmq e pgtap): cada migração revoga explicitamente o que cria, e a
-- checagem 5 de tools/ci/checagens.sql reprova qualquer função exposta a anon/authenticated fora da api.

-- ---------- Eventos ----------
create table fin.events (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  starts_on   date not null,
  ends_on     date not null,
  timezone    text not null default 'America/Sao_Paulo' check (timezone = 'America/Sao_Paulo'),
  archived_at timestamptz,
  created_at  timestamptz not null default now(),
  check (ends_on >= starts_on)
);

-- ---------- Papéis por evento, com vigência ----------
create table fin.user_roles (
  id          bigserial primary key,
  event_id    uuid not null references fin.events(id) on delete restrict,
  user_id     uuid not null references auth.users(id) on delete restrict,
  role        text not null check (role in ('operador_caixa','gestor','aprovador','admin','importador','catraca')),
  valid_from  timestamptz not null default now(),
  valid_to    timestamptz,
  granted_by  uuid references auth.users(id),
  granted_at  timestamptz not null default now(),
  check (valid_to is null or valid_to > valid_from)
);
create index on fin.user_roles(user_id, event_id);

-- Papéis que exigem MFA (aal2 no JWT do Supabase Auth).
create or replace function fin.role_requires_mfa(p_role text) returns boolean
language sql immutable as $$ select p_role in ('admin','aprovador') $$;

create or replace function fin.has_role(p_event uuid, p_role text) returns boolean
language sql stable security definer set search_path = fin, pg_temp as $$
  select exists (
    select 1 from fin.user_roles r
     where r.event_id = p_event and r.user_id = auth.uid() and r.role = p_role
       and r.valid_from <= now() and (r.valid_to is null or r.valid_to > now())
  )
  and (not fin.role_requires_mfa(p_role) or coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
$$;

-- Lança erro se o usuário não tiver nenhum dos papéis. Toda RPC da api começa por aqui.
create or replace function fin.require_role(p_event uuid, variadic p_roles text[]) returns void
language plpgsql stable security definer set search_path = fin, pg_temp as $$
declare r text;
begin
  if auth.uid() is null then
    raise exception 'não autenticado' using errcode = '28000';
  end if;
  foreach r in array p_roles loop
    if fin.has_role(p_event, r) then return; end if;
  end loop;
  raise exception 'acesso negado: exige um dos papéis % (admin e aprovador exigem MFA)', p_roles
    using errcode = '42501';
end $$;

alter table fin.events enable row level security;
alter table fin.user_roles enable row level security;

revoke all on all functions in schema fin from public, anon, authenticated;
