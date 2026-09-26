-- Auditoria genérica, assinaturas com vigência e fechamento do dia (03, seções 3.5 e 4).

-- ---------- Auditoria ----------
create table audit.log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  actor       uuid default auth.uid(),
  table_name  text not null,
  op          text not null,
  row_pk      text,
  old_row     jsonb,
  new_row     jsonb
);
alter table audit.log enable row level security;

create or replace function audit.trg() returns trigger
language plpgsql security definer set search_path = audit, pg_temp as $$
begin
  insert into audit.log(table_name, op, row_pk, old_row, new_row)
  values (tg_table_schema || '.' || tg_table_name, tg_op,
          coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id', to_jsonb(new)->>'event_id'),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create or replace function audit.forbid_mutation() returns trigger
language plpgsql as $$
begin raise exception 'audit.log é append-only' using errcode = '42501'; end $$;
create trigger log_no_update before update or delete on audit.log
  for each row execute function audit.forbid_mutation();
create trigger log_no_truncate before truncate on audit.log
  for each statement execute function audit.forbid_mutation();

create trigger audit after insert or update or delete on fin.events         for each row execute function audit.trg();
create trigger audit after insert or update or delete on fin.user_roles     for each row execute function audit.trg();
create trigger audit after insert or update or delete on fin.event_settings for each row execute function audit.trg();
create trigger audit after insert or update or delete on fin.accounts       for each row execute function audit.trg();
create trigger audit after insert or update or delete on fin.periods        for each row execute function audit.trg();

revoke all on all tables in schema audit from public, anon, authenticated;
revoke update, delete, truncate on audit.log from service_role;

-- ---------- Assinantes designados, com vigência ----------
create table fin.closure_signer_designations (
  id            bigserial primary key,
  event_id      uuid not null references fin.events(id) on delete restrict,
  user_id       uuid not null references auth.users(id) on delete restrict,
  valid_from    timestamptz not null default now(),
  valid_to      timestamptz,
  designated_by uuid references auth.users(id),
  check (valid_to is null or valid_to > valid_from)
);
create trigger audit after insert or update or delete on fin.closure_signer_designations
  for each row execute function audit.trg();
create trigger designations_no_delete before delete on fin.closure_signer_designations
  for each row execute function fin.forbid_mutation();

create table fin.period_signatures (
  event_id        uuid not null,
  business_date   date not null,
  signer_id       uuid not null references auth.users(id) on delete restrict,
  signed_at       timestamptz not null default clock_timestamp(),
  snapshot_sha256 bytea not null,
  comment         text,
  primary key (event_id, business_date, signer_id, snapshot_sha256),
  foreign key (event_id, business_date) references fin.periods(event_id, business_date) on delete restrict
);
create trigger period_signatures_no_update before update or delete on fin.period_signatures
  for each row execute function fin.forbid_mutation();

alter table fin.closure_signer_designations enable row level security;
alter table fin.period_signatures enable row level security;
revoke all on fin.closure_signer_designations, fin.period_signatures from public, anon, authenticated;

-- Hash do conteúdo financeiro do dia.
create or replace function fin.day_snapshot(p_event uuid, p_date date) returns bytea
language sql stable security definer set search_path = fin, extensions, pg_temp as $$
  select sha256(convert_to(coalesce(string_agg(
           e.id::text || ':' || p.account_id || ':' || p.side || ':' || p.amount_cents,
           '|' order by e.id, p.id), ''), 'UTF8'))
    from fin.journal_entries e join fin.postings p on p.entry_id = e.id
   where e.event_id = p_event and e.business_date = p_date
$$;

create or replace function fin.is_designated(p_event uuid, p_user uuid, p_at timestamptz) returns boolean
language sql stable security definer set search_path = fin, pg_temp as $$
  select exists (select 1 from fin.closure_signer_designations d
                  where d.event_id = p_event and d.user_id = p_user
                    and d.valid_from <= p_at and (d.valid_to is null or d.valid_to > p_at))
$$;

-- Só assina quem está designado no instante da assinatura.
create or replace function fin.trg_signer_designated() returns trigger
language plpgsql as $$
begin
  if not fin.is_designated(new.event_id, new.signer_id, new.signed_at) then
    raise exception 'Usuário % não está designado para assinar o fechamento em %', new.signer_id, new.signed_at
      using errcode = '42501';
  end if;
  return new;
end $$;
create trigger period_signatures_designated before insert on fin.period_signatures
  for each row execute function fin.trg_signer_designated();

-- ========== API (única superfície exposta) ==========

-- Designa um assinante. No máximo 2 designações vigentes por evento.
create or replace function api.designate_signer(p_event uuid, p_user uuid) returns bigint
language plpgsql security definer set search_path = fin, pg_temp as $$
declare v_id bigint; n int;
begin
  perform fin.require_role(p_event, 'admin');
  update fin.closure_signer_designations set valid_to = clock_timestamp()
   where event_id = p_event and user_id = p_user and valid_to is null;
  select count(*) into n from fin.closure_signer_designations
   where event_id = p_event and valid_to is null;
  if n >= 2 then
    raise exception 'já existem 2 assinantes designados; encerre uma designação antes' using errcode = '23514';
  end if;
  insert into fin.closure_signer_designations(event_id, user_id, valid_from, designated_by)
  values (p_event, p_user, clock_timestamp(), auth.uid()) returning id into v_id;
  return v_id;
end $$;

create or replace function api.end_signer_designation(p_event uuid, p_user uuid) returns void
language plpgsql security definer set search_path = fin, pg_temp as $$
begin
  perform fin.require_role(p_event, 'admin');
  update fin.closure_signer_designations set valid_to = clock_timestamp()
   where event_id = p_event and user_id = p_user and valid_to is null;
end $$;

-- Assina o conteúdo atual do dia. Quem lançou algo no dia não assina (separação de funções).
create or replace function api.sign_day(p_event uuid, p_date date, p_comment text default null) returns bytea
language plpgsql security definer set search_path = fin, pg_temp as $$
declare v_hash bytea; v_seg boolean;
begin
  perform fin.require_role(p_event, 'aprovador');
  if exists (select 1 from fin.periods where event_id = p_event and business_date = p_date and status = 'closed') then
    raise exception 'dia % já está fechado', p_date using errcode = '55000';
  end if;
  insert into fin.periods(event_id, business_date) values (p_event, p_date) on conflict do nothing;
  select coalesce(enforce_segregation, true) into v_seg from fin.event_settings where event_id = p_event;
  if coalesce(v_seg, true) and exists (
       select 1 from fin.journal_entries
        where event_id = p_event and business_date = p_date and created_by = auth.uid()) then
    raise exception 'separação de funções: quem lançou no dia % não pode assiná-lo', p_date
      using errcode = '42501';
  end if;
  v_hash := fin.day_snapshot(p_event, p_date);
  insert into fin.period_signatures(event_id, business_date, signer_id, snapshot_sha256, comment)
  values (p_event, p_date, auth.uid(), v_hash, p_comment)
  on conflict do nothing;
  return v_hash;
end $$;

-- Fecha o dia: exige 2 assinantes distintos sobre o conteúdo atual.
create or replace function api.close_day(p_event uuid, p_date date) returns bytea
language plpgsql security definer set search_path = fin, pg_temp as $$
declare v_hash bytea; n int;
begin
  perform fin.require_role(p_event, 'aprovador', 'admin');
  -- trava o período para que nenhum lançamento entre entre o cálculo do hash e o fechamento
  perform 1 from fin.periods where event_id = p_event and business_date = p_date for update;
  v_hash := fin.day_snapshot(p_event, p_date);
  select count(distinct signer_id) into n
    from fin.period_signatures
   where event_id = p_event and business_date = p_date and snapshot_sha256 = v_hash;
  if n < 2 then
    raise exception 'Fechamento de % exige 2 assinaturas distintas sobre o conteúdo atual (tem %)', p_date, n
      using errcode = '55000';
  end if;
  update fin.periods set status = 'closed', closed_at = now(), closed_by = auth.uid(), snapshot_sha256 = v_hash
   where event_id = p_event and business_date = p_date and status <> 'closed';
  if not found then raise exception 'Dia % inexistente ou já fechado', p_date using errcode = '55000'; end if;
  return v_hash;
end $$;

-- Reabre: só admin (com MFA), com motivo, e quem assinou o fechamento não reabre.
create or replace function api.reopen_day(p_event uuid, p_date date, p_reason text) returns void
language plpgsql security definer set search_path = fin, pg_temp as $$
declare p fin.periods;
begin
  perform fin.require_role(p_event, 'admin');
  select * into p from fin.periods where event_id = p_event and business_date = p_date for update;
  if p.status is distinct from 'closed' then
    raise exception 'dia % não está fechado', p_date using errcode = '55000';
  end if;
  if exists (select 1 from fin.period_signatures
              where event_id = p_event and business_date = p_date
                and snapshot_sha256 = p.snapshot_sha256 and signer_id = auth.uid()) then
    raise exception 'separação de funções: quem assinou o dia % não pode reabri-lo', p_date using errcode = '42501';
  end if;
  insert into fin.period_reopenings(event_id, business_date, reopened_by, reason, previous_sha256)
  values (p_event, p_date, auth.uid(), p_reason, p.snapshot_sha256);
  update fin.periods set status = 'open', closed_at = null, closed_by = null, snapshot_sha256 = null
   where event_id = p_event and business_date = p_date;
end $$;

-- Leitura: saldos do evento (sem somas no navegador).
create or replace function api.account_balances(p_event uuid)
returns table (code text, name text, type text, balance_cents bigint)
language plpgsql stable security definer set search_path = fin, pg_temp as $$
begin
  perform fin.require_role(p_event, 'gestor', 'aprovador', 'admin');
  return query select b.code, b.name, b.type, b.balance_cents
                 from fin.v_account_balances b where b.event_id = p_event order by b.code;
end $$;

revoke all on all functions in schema fin, audit from public, anon, authenticated;
revoke all on all functions in schema api from public, anon;
grant execute on function
  api.designate_signer(uuid, uuid), api.end_signer_designation(uuid, uuid),
  api.sign_day(uuid, date, text), api.close_day(uuid, date),
  api.reopen_day(uuid, date, text), api.account_balances(uuid)
  to authenticated;
