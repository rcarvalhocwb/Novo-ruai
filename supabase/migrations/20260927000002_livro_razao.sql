-- Livro-razão de partidas dobradas, append-only (03-ARQUITETURA-ALVO.md, seções 3 e 4).
-- Dinheiro sempre em centavos (bigint). Nenhum UPDATE/DELETE: correção só por estorno.

-- ---------- Configuração do evento ----------
create table fin.event_settings (
  event_id                   uuid primary key references fin.events(id) on delete restrict,
  min_cash_cents             bigint not null default 100000 check (min_cash_cents >= 0),
  cash_diff_optional_cents   bigint not null default 100    check (cash_diff_optional_cents >= 0),   -- até R$ 1,00
  cash_diff_highlight_cents  bigint not null default 5000   check (cash_diff_highlight_cents >= cash_diff_optional_cents), -- acima de R$ 50,00
  box_office_ticket_control  text   not null default 'total' check (box_office_ticket_control in ('total','por_guiche')),
  box_office_alert_bps       int    not null default 500  check (box_office_alert_bps between 0 and 10000),
  box_office_critical_bps    int    not null default 1000 check (box_office_critical_bps >= box_office_alert_bps),
  enforce_segregation        boolean not null default true,   -- quem lança no dia não assina o dia
  updated_by                 uuid references auth.users(id),
  updated_at                 timestamptz not null default now()
);

-- ---------- Plano de contas ----------
create table fin.accounts (
  id            bigserial primary key,
  event_id      uuid not null references fin.events(id) on delete restrict,
  code          text not null,
  name          text not null,
  type          text not null check (type in ('asset','liability','equity','revenue','expense')),
  normal_side   char(1) not null check (normal_side in ('D','C')),
  counterparty  text,                         -- 'zet' | 'pagbank' | 'store:<uuid>' | 'cashier:<n>' | 'bank:<id>' | 'treasury'
  archived_at   timestamptz,
  unique (event_id, code)
);

-- ---------- Períodos (dia operacional, America/Sao_Paulo) ----------
create table fin.periods (
  event_id        uuid not null references fin.events(id) on delete restrict,
  business_date   date not null,
  status          text not null default 'open' check (status in ('open','closed')),
  closed_at       timestamptz,
  closed_by       uuid references auth.users(id),
  snapshot_sha256 bytea,
  primary key (event_id, business_date)
);

create table fin.period_reopenings (
  id            bigserial primary key,
  event_id      uuid not null,
  business_date date not null,
  reopened_at   timestamptz not null default now(),
  reopened_by   uuid not null references auth.users(id),
  reason        text not null check (length(btrim(reason)) >= 10),
  previous_sha256 bytea,
  foreign key (event_id, business_date) references fin.periods(event_id, business_date) on delete restrict
);

-- ---------- Lançamentos e partidas ----------
create table fin.journal_entries (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references fin.events(id) on delete restrict,
  business_date     date not null,
  occurred_at       timestamptz not null,
  recorded_at       timestamptz not null default now(),
  kind              text not null,
  description       text not null,
  idempotency_key   text not null unique,
  source_type       text,
  source_id         text,
  reverses_entry_id uuid references fin.journal_entries(id) on delete restrict,
  created_by        uuid references auth.users(id),
  metadata          jsonb not null default '{}'
);
create unique index journal_entries_one_reversal
  on fin.journal_entries(reverses_entry_id) where reverses_entry_id is not null;
create index on fin.journal_entries(event_id, business_date);
create index on fin.journal_entries(source_type, source_id);

create table fin.postings (
  id            bigserial primary key,
  entry_id      uuid not null references fin.journal_entries(id) on delete restrict,
  account_id    bigint not null references fin.accounts(id) on delete restrict,
  side          char(1) not null check (side in ('D','C')),
  amount_cents  bigint not null check (amount_cents > 0),
  currency      char(3) not null default 'BRL' check (currency = 'BRL')
);
create index on fin.postings(account_id);
create index on fin.postings(entry_id);

-- ---------- Invariante: lançamento balanceado, checado no COMMIT ----------
create or replace function fin.assert_entry_balanced(p_entry uuid) returns void
language plpgsql as $$
declare d bigint; c bigint; n int; ev uuid; bad int;
begin
  select coalesce(sum(amount_cents) filter (where side = 'D'), 0),
         coalesce(sum(amount_cents) filter (where side = 'C'), 0),
         count(*)
    into d, c, n
    from fin.postings where entry_id = p_entry;
  if n < 2 or d <> c then
    raise exception 'Lançamento % desbalanceado: D=% C=% partidas=%', p_entry, d, c, n
      using errcode = '23514';
  end if;
  -- toda partida tem de ser de conta do mesmo evento do lançamento
  select e.event_id into ev from fin.journal_entries e where e.id = p_entry;
  select count(*) into bad
    from fin.postings p join fin.accounts a on a.id = p.account_id
   where p.entry_id = p_entry and a.event_id <> ev;
  if bad > 0 then
    raise exception 'Lançamento % usa conta de outro evento', p_entry using errcode = '23514';
  end if;
end $$;

create or replace function fin.trg_posting_balanced() returns trigger
language plpgsql as $$ begin perform fin.assert_entry_balanced(new.entry_id); return null; end $$;

create or replace function fin.trg_entry_has_postings() returns trigger
language plpgsql as $$ begin perform fin.assert_entry_balanced(new.id); return null; end $$;

create constraint trigger postings_balanced
  after insert on fin.postings deferrable initially deferred
  for each row execute function fin.trg_posting_balanced();
create constraint trigger entries_have_postings
  after insert on fin.journal_entries deferrable initially deferred
  for each row execute function fin.trg_entry_has_postings();

-- ---------- Imutabilidade (vale inclusive para o dono das tabelas) ----------
create or replace function fin.forbid_mutation() returns trigger
language plpgsql as $$
begin
  raise exception '% é append-only: corrija com lançamento de estorno', tg_table_name
    using errcode = '42501';
end $$;

create trigger je_no_update before update or delete on fin.journal_entries
  for each row execute function fin.forbid_mutation();
create trigger je_no_truncate before truncate on fin.journal_entries
  for each statement execute function fin.forbid_mutation();
create trigger p_no_update before update or delete on fin.postings
  for each row execute function fin.forbid_mutation();
create trigger p_no_truncate before truncate on fin.postings
  for each statement execute function fin.forbid_mutation();
create trigger reopen_no_update before update or delete on fin.period_reopenings
  for each row execute function fin.forbid_mutation();
create trigger accounts_no_delete before delete on fin.accounts
  for each row execute function fin.forbid_mutation();

-- Conta: só nome e archived_at podem mudar (código, tipo e lado nunca).
create or replace function fin.trg_account_guard() returns trigger
language plpgsql as $$
begin
  if new.event_id <> old.event_id or new.code <> old.code or new.type <> old.type
     or new.normal_side <> old.normal_side then
    raise exception 'conta %: código, tipo, natureza e evento são imutáveis', old.code using errcode = '42501';
  end if;
  return new;
end $$;
create trigger accounts_guard before update on fin.accounts
  for each row execute function fin.trg_account_guard();

-- ---------- Trava de período ----------
create or replace function fin.trg_period_open() returns trigger
language plpgsql as $$
declare v_status text;
begin
  -- garante que o período existe (aberto)
  insert into fin.periods(event_id, business_date) values (new.event_id, new.business_date)
  on conflict do nothing;
  -- FOR SHARE espera um close_day em andamento (que segura FOR UPDATE) e lê o status já fechado
  select p.status into v_status from fin.periods p
   where p.event_id = new.event_id and p.business_date = new.business_date
   for share;
  if v_status = 'closed' then
    raise exception 'Dia % está fechado. Lance o ajuste em um dia aberto referenciando o original.',
      new.business_date using errcode = '55000';
  end if;
  return new;
end $$;
create trigger je_period_open before insert on fin.journal_entries
  for each row execute function fin.trg_period_open();

-- ---------- Saldos (derivados, nunca digitados) ----------
create view fin.v_account_balances as
select a.event_id, a.id as account_id, a.code, a.name, a.type, a.counterparty,
       coalesce(sum(case when p.side = a.normal_side then p.amount_cents else -p.amount_cents end), 0)::bigint
         as balance_cents
  from fin.accounts a
  left join fin.postings p on p.account_id = a.id
 group by a.id;

create view fin.v_daily_account_movements as
select e.event_id, e.business_date, p.account_id,
       coalesce(sum(p.amount_cents) filter (where p.side = 'D'), 0)::bigint as debit_cents,
       coalesce(sum(p.amount_cents) filter (where p.side = 'C'), 0)::bigint as credit_cents
  from fin.journal_entries e
  join fin.postings p on p.entry_id = e.id
 group by 1, 2, 3;

-- ---------- Única porta de escrita no livro-razão ----------
-- Não é executável por nenhum papel de cliente: só por funções api.* e pelos processadores.
-- p_lines: [{"account_code":"1.2.01","side":"D","amount_cents":10000}, ...]
create or replace function fin.post_entry(
  p_event uuid, p_business_date date, p_occurred_at timestamptz,
  p_kind text, p_description text, p_idempotency_key text,
  p_source_type text, p_source_id text, p_lines jsonb,
  p_reverses uuid default null, p_metadata jsonb default '{}'
) returns uuid
language plpgsql security definer set search_path = fin, pg_temp as $$
declare v_id uuid; l jsonb; v_amount bigint; v_acc bigint;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'lançamento exige ao menos 2 partidas' using errcode = '22023';
  end if;

  insert into fin.journal_entries(event_id, business_date, occurred_at, kind, description,
                                  idempotency_key, source_type, source_id, reverses_entry_id,
                                  created_by, metadata)
  values (p_event, p_business_date, p_occurred_at, p_kind, p_description,
          p_idempotency_key, p_source_type, p_source_id, p_reverses, auth.uid(), p_metadata)
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then  -- já lançado: idempotente
    select id into v_id from fin.journal_entries where idempotency_key = p_idempotency_key;
    return v_id;
  end if;

  for l in select * from jsonb_array_elements(p_lines) loop
    -- centavos inteiros: rejeita "10.5", "1e3" e números JSON não inteiros
    if jsonb_typeof(l->'amount_cents') <> 'number' or (l->>'amount_cents') !~ '^[0-9]+$' then
      raise exception 'amount_cents inválido: % (use centavos inteiros)', l->'amount_cents'
        using errcode = '22023';
    end if;
    v_amount := (l->>'amount_cents')::bigint;
    select a.id into v_acc
      from fin.accounts a
     where a.event_id = p_event and a.code = l->>'account_code' and a.archived_at is null;
    if v_acc is null then
      raise exception 'Conta % inexistente ou arquivada no evento %', l->>'account_code', p_event
        using errcode = '23503';
    end if;
    insert into fin.postings(entry_id, account_id, side, amount_cents)
    values (v_id, v_acc, l->>'side', v_amount);
  end loop;
  return v_id;
end $$;

-- Estorno: espelho exato do original, uma única vez, num dia aberto.
create or replace function fin.reverse_entry(p_entry uuid, p_business_date date, p_reason text)
returns uuid language plpgsql security definer set search_path = fin, pg_temp as $$
declare o fin.journal_entries; v_lines jsonb;
begin
  if length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception 'motivo do estorno obrigatório (mínimo 10 caracteres)' using errcode = '22023';
  end if;
  select * into o from fin.journal_entries where id = p_entry;
  if o.id is null then raise exception 'Lançamento % não existe', p_entry using errcode = '23503'; end if;
  if o.kind = 'reversal' then raise exception 'não se estorna um estorno' using errcode = '22023'; end if;
  select jsonb_agg(jsonb_build_object(
           'account_code', a.code,
           'side', case p.side when 'D' then 'C' else 'D' end,
           'amount_cents', p.amount_cents) order by p.id)
    into v_lines
    from fin.postings p join fin.accounts a on a.id = p.account_id
   where p.entry_id = p_entry;
  return fin.post_entry(o.event_id, p_business_date, now(), 'reversal',
                        'Estorno: ' || p_reason, 'reversal:' || p_entry,
                        'journal_entry', p_entry::text, v_lines, p_entry,
                        jsonb_build_object('reason', p_reason,
                                           'adjusts_business_date', o.business_date));
end $$;

-- ---------- Plano de contas padrão (03-ARQUITETURA-ALVO.md, 3.2) ----------
create or replace function fin.create_chart_of_accounts(p_event uuid) returns int
language plpgsql security definer set search_path = fin, pg_temp as $$
declare n int;
begin
  insert into fin.accounts(event_id, code, name, type, normal_side, counterparty)
  select p_event, c.code, c.name, c.type, c.side, c.cp
    from (values
      ('1.1.00','Tesouraria / cofre do evento','asset','D','treasury'),
      ('1.1.01','Caixa bilheteria 1','asset','D','cashier:1'),
      ('1.1.02','Caixa bilheteria 2','asset','D','cashier:2'),
      ('1.1.03','Caixa bilheteria 3','asset','D','cashier:3'),
      ('1.1.04','Caixa bilheteria 4','asset','D','cashier:4'),
      ('1.1.05','Caixa bilheteria 5','asset','D','cashier:5'),
      ('1.1.06','Caixa bilheteria 6','asset','D','cashier:6'),
      ('1.1.07','Caixa bilheteria 7','asset','D','cashier:7'),
      ('1.1.08','Caixa bilheteria 8','asset','D','cashier:8'),
      ('1.1.09','Caixa bilheteria 9','asset','D','cashier:9'),
      ('1.2.01','A receber – Zet','asset','D','zet'),
      ('1.2.02','A receber – PagBank','asset','D','pagbank'),
      ('2.1.01','Crédito de loja (repasse a maior)','liability','C',null),
      ('3.1.01','Repasses à administração','equity','D',null),
      ('4.1.01','Receita ingressos online','revenue','C',null),
      ('4.1.02','Receita ingressos bilheteria','revenue','C',null),
      ('4.1.03','Receita produtos bilheteria','revenue','C',null),
      ('4.1.04','Receita ingressos máquina da Zet','revenue','C',null),
      ('4.1.09','Sobra de caixa','revenue','C',null),
      ('4.2.01','Receita comissão foods','revenue','C',null),
      ('4.9.01','Estornos de ingressos online','revenue','D',null),
      ('4.9.02','Estornos da bilheteria','revenue','D',null),
      ('4.9.03','Contestações online (chargeback / PIX MED)','revenue','D',null),
      ('5.1.02','Taxa PagBank (MDR)','expense','D',null),
      ('5.1.03','Taxa de saque Zet','expense','D',null),
      ('5.2.01','Quebra de caixa','expense','D',null),
      ('5.2.02','Baixa de comissão não recebida','expense','D',null),
      ('5.9.01','Despesas operacionais','expense','D',null),
      ('5.9.99','Diferenças a apurar','expense','D',null)
    ) as c(code, name, type, side, cp)
  on conflict (event_id, code) do nothing;
  get diagnostics n = row_count;
  insert into fin.event_settings(event_id) values (p_event) on conflict do nothing;
  return n;
end $$;

-- ---------- Permissões: ninguém de fora escreve em fin ----------
alter table fin.event_settings    enable row level security;
alter table fin.accounts          enable row level security;
alter table fin.periods           enable row level security;
alter table fin.period_reopenings enable row level security;
alter table fin.journal_entries   enable row level security;
alter table fin.postings          enable row level security;

revoke all on all tables in schema fin from public, anon, authenticated;
revoke all on all functions in schema fin from public, anon, authenticated;
revoke update, delete, truncate on fin.journal_entries, fin.postings, fin.period_reopenings from service_role;
