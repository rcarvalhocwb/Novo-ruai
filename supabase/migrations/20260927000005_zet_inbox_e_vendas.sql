-- Entrega 2 (W-02, W-03): caixa de entrada imutável dos webhooks da Zet, de-para, projeção das vendas
-- e exceções de conciliação. Ver 04-INTEGRACAO-ZET.md, 09, 12 e 15.
--
-- Fila: a própria tabela integ.webhook_inbox (status + next_attempt_at, lida com FOR UPDATE SKIP LOCKED).
-- Não depende de pgmq: é durável, transacional e testável em Postgres puro.

-- ---------- Rateio pelo maior resto (mesma regra de packages/money: allocate) ----------
create or replace function fin.allocate(p_total bigint, p_weights bigint[]) returns bigint[]
language plpgsql immutable set search_path = fin, pg_temp as $$
declare
  n int := coalesce(array_length(p_weights, 1), 0);
  s bigint := 0; parts bigint[] := '{}'; left_ bigint; i int; k int;
  ord int[];
begin
  if p_total < 0 then raise exception 'total negativo' using errcode = '22023'; end if;
  if n = 0 then raise exception 'pesos inválidos' using errcode = '22023'; end if;
  for i in 1..n loop
    if p_weights[i] < 0 then raise exception 'pesos inválidos' using errcode = '22023'; end if;
    s := s + p_weights[i];
  end loop;
  if s <= 0 then raise exception 'pesos inválidos' using errcode = '22023'; end if;
  for i in 1..n loop parts := parts || ((p_total * p_weights[i]) / s); end loop;
  left_ := p_total - (select sum(x) from unnest(parts) x);
  -- maior resto primeiro; empate: menor índice
  select array_agg(idx order by r desc, idx) into ord
    from (select i2 as idx, (p_total * p_weights[i2]) % s as r from generate_series(1, n) i2) t;
  k := 1;
  while left_ > 0 loop
    parts[ord[k]] := parts[ord[k]] + 1;
    left_ := left_ - 1; k := k + 1;
  end loop;
  return parts;
end $$;

-- Converte número do JSON em centavos, exato (jsonb guarda decimal): rejeita mais de 2 casas.
create or replace function integ.to_cents_strict(p jsonb) returns bigint
language plpgsql immutable set search_path = integ, pg_temp as $$
declare v numeric;
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) <> 'number' then raise exception 'valor não numérico: %', p using errcode = '22023'; end if;
  v := (p #>> '{}')::numeric * 100;
  if v <> trunc(v) then raise exception 'mais de 2 casas decimais: %', p using errcode = '22023'; end if;
  return v::bigint;
end $$;

-- ---------- Caixa de entrada (fonte primária da venda online; nunca é apagada) ----------
create table integ.webhook_inbox (
  id              bigserial primary key,
  source          text not null check (source in ('zet','zet_hml')),
  received_at     timestamptz not null default now(),
  remote_ip       inet,
  headers         jsonb not null default '{}',
  raw_body        bytea not null,
  body_sha256     bytea not null,
  status          text not null default 'pending'
                  check (status in ('pending','processed','failed','dead')),
  attempts        int not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error      text,
  processed_at    timestamptz,
  outcome         text,                -- venda | venda_repetida | estorno | estorno_repetido | excecao
  unique (source, body_sha256)
);
create index webhook_inbox_fila on integ.webhook_inbox (next_attempt_at) where status in ('pending','failed');

create or replace function integ.trg_inbox_guard() returns trigger
language plpgsql set search_path = integ, pg_temp as $$
begin
  if tg_op = 'DELETE' then raise exception 'webhook_inbox não pode ser apagado' using errcode = '42501'; end if;
  if new.raw_body is distinct from old.raw_body or new.headers is distinct from old.headers
     or new.body_sha256 is distinct from old.body_sha256 or new.received_at is distinct from old.received_at
     or new.source is distinct from old.source or new.remote_ip is distinct from old.remote_ip then
    raise exception 'conteúdo do webhook é imutável' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger inbox_guard before update or delete on integ.webhook_inbox
  for each row execute function integ.trg_inbox_guard();
create trigger inbox_no_truncate before truncate on integ.webhook_inbox
  for each statement execute function fin.forbid_mutation();

-- Recebe do consumidor da fila (1 INSERT idempotente). Chamado só pelo papel técnico ingest_writer.
create or replace function integ.receive_webhook(
  p_source text, p_raw_body_b64 text, p_body_sha256_hex text,
  p_headers jsonb, p_remote_ip text, p_received_at timestamptz
) returns bigint
language plpgsql security definer set search_path = integ, extensions, pg_temp as $$
declare v_id bigint; v_body bytea := decode(p_raw_body_b64, 'base64');
begin
  if encode(sha256(v_body), 'hex') <> lower(p_body_sha256_hex) then
    raise exception 'sha256 não confere com o corpo' using errcode = '22023';
  end if;
  insert into integ.webhook_inbox(source, received_at, remote_ip, headers, raw_body, body_sha256)
  values (p_source, coalesce(p_received_at, now()), nullif(p_remote_ip, '')::inet,
          coalesce(p_headers, '{}'), v_body, decode(p_body_sha256_hex, 'hex'))
  on conflict (source, body_sha256) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from integ.webhook_inbox
     where source = p_source and body_sha256 = decode(p_body_sha256_hex, 'hex');
  end if;
  return v_id;
end $$;

-- ---------- De-para (NUNCA por nome ou texto de descrição) ----------
create table integ.zet_event_map (
  zet_event_id  bigint not null,
  source        text not null default 'zet' check (source in ('zet','zet_hml')),
  event_id      uuid not null references fin.events(id) on delete restrict,
  primary key (source, zet_event_id)
);

create table integ.zet_ticket_type_map (
  zet_events_value_id bigint primary key,   -- eventsValues.id: um por data, sessão e tipo
  zet_event_id        bigint not null,
  description         text not null,        -- texto original, só referência
  category            text not null,        -- inteira, meia, solidario, gazeta, cortesia...
  list_price_cents    bigint not null check (list_price_cents >= 0)  -- preço líquido de tabela
);

-- ---------- Projeção das vendas (o histórico está no inbox e no livro-razão) ----------
create table sales.zet_orders (
  order_uuid         uuid primary key,
  zet_order_id       bigint,                 -- informativo; a chave é o uuid (nunca recusar venda paga por isso)
  event_id           uuid not null references fin.events(id) on delete restrict,
  status             text not null check (status in ('PAGO','PARCIALMENTE_ESTORNADO','ESTORNADO','CONTESTADO')),
  channel            text not null default 'online' check (channel in ('online','zet_maquina','cortesia')),
  source             text not null default 'webhook' check (source in ('webhook','zet_export','recovery')),
  gross_cents        bigint not null check (gross_cents >= 0),
  fee_cents          bigint not null check (fee_cents >= 0 and fee_cents <= gross_cents),
  discount_cents     bigint not null default 0 check (discount_cents >= 0),
  net_cents          bigint generated always as (gross_cents - fee_cents) stored,
  payment_type       text not null,
  is_courtesy        boolean not null,
  paid_at            timestamptz not null,
  business_date      date not null,
  refunded_at        timestamptz,
  items_pending      boolean not null default false,
  created_from_inbox bigint references integ.webhook_inbox(id) on delete restrict,
  updated_from_inbox bigint references integ.webhook_inbox(id) on delete restrict,
  created_at         timestamptz not null default now()
);
create index on sales.zet_orders(event_id, business_date);
create index on sales.zet_orders(zet_order_id);

create table sales.zet_order_items (
  voucher            text primary key,
  order_uuid         uuid not null references sales.zet_orders(order_uuid) on delete restrict,
  zet_events_value_id bigint,
  category           text not null,
  net_cents          bigint not null check (net_cents >= 0),
  status             text not null check (status in ('valid','cancelled','contested')),
  visit_date         date,
  session_label      text,
  sold_on            date not null,
  refunded_on        date,
  used_at            timestamptz,
  used_source        text check (used_source in ('zet_painel','catraca','zet_api'))
);
create index on sales.zet_order_items(order_uuid);
create index on sales.zet_order_items(visit_date);

create trigger audit after insert or update or delete on sales.zet_orders
  for each row execute function audit.trg();
create trigger zet_orders_no_delete before delete on sales.zet_orders
  for each row execute function fin.forbid_mutation();
create trigger zet_items_no_delete before delete on sales.zet_order_items
  for each row execute function fin.forbid_mutation();

-- ---------- Exceções de conciliação (nunca sobrescrevem venda; esperam decisão humana) ----------
create table recon.exceptions (
  id             bigserial primary key,
  event_id       uuid references fin.events(id) on delete restrict,
  kind           text not null,   -- amount_mismatch | taxa_divergente | preco_divergente | estorno_orfao | cp_apos_es | voucher_desconhecido ...
  ref            text not null,
  expected_cents bigint,
  actual_cents   bigint,
  detail         jsonb not null default '{}',
  source_inbox   bigint references integ.webhook_inbox(id) on delete restrict,
  status         text not null default 'open' check (status in ('open','resolved','written_off')),
  resolution     text,
  resolved_by    uuid references auth.users(id),
  resolved_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (kind, ref)
);
create trigger audit after insert or update or delete on recon.exceptions
  for each row execute function audit.trg();
create trigger exceptions_no_delete before delete on recon.exceptions
  for each row execute function fin.forbid_mutation();

create or replace function recon.open_exception(
  p_event uuid, p_kind text, p_ref text, p_expected bigint, p_actual bigint, p_detail jsonb, p_inbox bigint
) returns void
language sql security definer set search_path = recon, pg_temp as $$
  insert into recon.exceptions(event_id, kind, ref, expected_cents, actual_cents, detail, source_inbox)
  values (p_event, p_kind, p_ref, p_expected, p_actual, coalesce(p_detail, '{}'), p_inbox)
  on conflict (kind, ref) do nothing
$$;

-- ---------- Dia de lançamento: o do fato; se estiver fechado, o dia aberto de hoje ----------
create or replace function fin.posting_date(p_event uuid, p_fact_date date) returns date
language sql stable security definer set search_path = fin, pg_temp as $$
  select case when exists (select 1 from fin.periods
                            where event_id = p_event and business_date = p_fact_date and status = 'closed')
              then (now() at time zone 'America/Sao_Paulo')::date
              else p_fact_date end
$$;

-- ========== Processador (1 webhook por transação; 1 pedido por vez com advisory lock) ==========
create or replace function integ.process_inbox(p_id bigint) returns text
language plpgsql security definer set search_path = integ, sales, fin, recon, pg_temp as $$
declare
  ib integ.webhook_inbox; body jsonb; ord jsonb; tickets jsonb; t jsonb;
  v_action text; v_uuid uuid; v_event uuid; v_zet_event bigint;
  v_gross bigint; v_fee bigint; v_disc bigint; v_net bigint;
  v_paid timestamptz; v_bdate date; v_post date; v_courtesy boolean; v_ptype text;
  o sales.zet_orders; it sales.zet_order_items;
  v_weights bigint[] := '{}'; v_cats text[] := '{}'; v_parts bigint[];
  v_list_sum bigint := 0; v_expected_fee bigint; n int; i int; v_map integ.zet_ticket_type_map;
  v_remaining int; v_refund_day date; v_outcome text;
begin
  select * into ib from integ.webhook_inbox where id = p_id;
  if ib.id is null then raise exception 'inbox % não existe', p_id; end if;
  if ib.status in ('processed','dead') then return ib.outcome; end if;

  body := convert_from(ib.raw_body, 'UTF8')::jsonb;
  v_action := body->>'action';
  ord := body->'data'->'order';
  tickets := coalesce(body->'data'->'eventTicketCodes', '[]'::jsonb);
  v_uuid := (ord->>'uuid')::uuid;
  v_zet_event := (body->'data'->'event'->>'id')::bigint;

  if v_action not in ('CP','ES') or v_uuid is null then
    raise exception 'payload sem action CP/ES ou sem order.uuid';
  end if;

  select event_id into v_event from integ.zet_event_map
   where zet_event_id = v_zet_event and source = ib.source;
  if v_event is null then
    raise exception 'evento Zet % sem mapeamento', v_zet_event;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uuid::text, 0));
  select * into o from sales.zet_orders where order_uuid = v_uuid;

  -- ---------------- CP: compra paga ----------------
  if v_action = 'CP' then
    v_gross := integ.to_cents_strict(ord->'totalValue');
    v_fee   := coalesce(integ.to_cents_strict(ord->'totalTax'), 0);
    v_disc  := coalesce(integ.to_cents_strict(ord->'discount'), 0);
    if v_gross is null or v_fee < 0 or v_fee > v_gross then
      raise exception 'valores inválidos: totalValue=% totalTax=%', ord->'totalValue', ord->'totalTax';
    end if;

    if o.order_uuid is not null then
      if o.gross_cents = v_gross and o.fee_cents = v_fee then
        if o.status <> 'PAGO' then
          perform recon.open_exception(v_event, 'cp_apos_es', v_uuid::text, null, null,
                                       jsonb_build_object('status', o.status), p_id);
        end if;
        v_outcome := 'venda_repetida';
      else
        -- nunca sobrescreve: o primeiro CP válido vale
        perform recon.open_exception(v_event, 'amount_mismatch', v_uuid::text || ':' || p_id,
                                     o.net_cents, v_gross - v_fee,
                                     jsonb_build_object('gross', v_gross, 'fee', v_fee), p_id);
        v_outcome := 'excecao';
      end if;
    else
      v_paid := coalesce(nullif(ord->>'paymentConfirmeDate', '')::timestamptz,
                         nullif(ord->>'createdAt', '')::timestamptz);
      if v_paid is null then raise exception 'pedido % sem data de pagamento', v_uuid; end if;
      v_bdate := (v_paid at time zone 'America/Sao_Paulo')::date;
      v_net := v_gross - v_fee;
      v_ptype := coalesce(ord->>'paymentType', 'DESCONHECIDO');
      v_courtesy := v_ptype = 'CORTESIA' or v_gross = 0;
      n := jsonb_array_length(tickets);
      if n = 0 then raise exception 'pedido % sem ingressos', v_uuid; end if;

      for i in 0..n-1 loop
        t := tickets->i;
        select * into v_map from integ.zet_ticket_type_map
         where zet_events_value_id = (t->'eventsValues'->>'id')::bigint;
        if v_map.zet_events_value_id is null then
          raise exception 'tipo de ingresso Zet % sem mapeamento', t->'eventsValues'->>'id';
        end if;
        v_weights := v_weights || v_map.list_price_cents;
        v_cats := v_cats || v_map.category;
        v_list_sum := v_list_sum + v_map.list_price_cents;
      end loop;

      if v_net = 0 then
        v_parts := array_fill(0::bigint, array[n]);
      elsif v_list_sum > 0 then
        v_parts := fin.allocate(v_net, v_weights);
      else
        v_parts := fin.allocate(v_net, array_fill(1::bigint, array[n]));
      end if;

      insert into sales.zet_orders(order_uuid, zet_order_id, event_id, status, channel, source,
                                   gross_cents, fee_cents, discount_cents, payment_type, is_courtesy,
                                   paid_at, business_date, created_from_inbox, updated_from_inbox)
      values (v_uuid, nullif(ord->>'id', '')::bigint, v_event, 'PAGO',
              case when v_courtesy then 'cortesia' else 'online' end, 'webhook',
              v_gross, v_fee, v_disc, v_ptype, v_courtesy, v_paid, v_bdate, p_id, p_id);

      for i in 0..n-1 loop
        t := tickets->i;
        insert into sales.zet_order_items(voucher, order_uuid, zet_events_value_id, category, net_cents,
                                          status, visit_date, session_label, sold_on)
        values (t->>'voucher', v_uuid, (t->'eventsValues'->>'id')::bigint, v_cats[i+1], v_parts[i+1], 'valid',
                (nullif(t->'eventsValues'->'eventsDates'->>'startDate', '')::timestamptz
                   at time zone 'America/Sao_Paulo')::date,
                t->'eventsValues'->>'session', v_bdate);
      end loop;

      -- validações que abrem exceção sem bloquear a venda
      v_expected_fee := (v_net * 1000 + 5000) / 10000;       -- 10% sobre o líquido, meio-para-cima
      if abs(v_fee - v_expected_fee) > n and not v_courtesy then
        perform recon.open_exception(v_event, 'taxa_divergente', v_uuid::text, v_expected_fee, v_fee, '{}', p_id);
      end if;
      if not v_courtesy and v_net <> v_list_sum - v_disc then
        perform recon.open_exception(v_event, 'preco_divergente', v_uuid::text, v_list_sum - v_disc, v_net, '{}', p_id);
      end if;

      if v_net > 0 then
        v_post := fin.posting_date(v_event, v_bdate);
        perform fin.post_entry(v_event, v_post, v_paid, 'zet_sale', 'Venda Zet ' || v_uuid,
                               'zet:CP:' || v_uuid, 'zet_order', v_uuid::text,
                               jsonb_build_array(
                                 jsonb_build_object('account_code','1.2.01','side','D','amount_cents',v_net),
                                 jsonb_build_object('account_code','4.1.01','side','C','amount_cents',v_net)),
                               null,
                               case when v_post <> v_bdate then jsonb_build_object('adjusts_business_date', v_bdate)
                                    else '{}'::jsonb end);
      end if;
      v_outcome := 'venda';
    end if;

  -- ---------------- ES: estorno (por voucher; o evento devolve só o preço do ingresso) ----------------
  else
    if o.order_uuid is null then
      -- o CP pode chegar depois: registra a exceção e agenda nova tentativa (sem desfazer a exceção)
      perform recon.open_exception(v_event, 'estorno_orfao', v_uuid::text, null, null, '{}', p_id);
      update integ.webhook_inbox
         set status = case when attempts + 1 >= 8 then 'dead' else 'failed' end,
             attempts = attempts + 1,
             last_error = 'estorno órfão: pedido ainda não existe',
             next_attempt_at = now() + interval '15 minutes'
       where id = p_id;
      return 'estorno_orfao';
    end if;
    v_refund_day := (ib.received_at at time zone 'America/Sao_Paulo')::date;
    v_outcome := 'estorno_repetido';
    n := jsonb_array_length(tickets);
    for i in 0..n-1 loop
      t := tickets->i;
      select * into it from sales.zet_order_items where voucher = t->>'voucher';
      if it.voucher is null or it.order_uuid <> v_uuid then
        perform recon.open_exception(v_event, 'voucher_desconhecido', v_uuid::text || ':' || coalesce(t->>'voucher','?'),
                                     null, null, '{}', p_id);
        continue;
      end if;
      if it.status = 'valid' then
        update sales.zet_order_items set status = 'cancelled', refunded_on = v_refund_day where voucher = it.voucher;
        if it.net_cents > 0 then
          v_post := fin.posting_date(v_event, v_refund_day);
          perform fin.post_entry(v_event, v_post, ib.received_at, 'zet_refund',
                                 'Estorno Zet ' || v_uuid || ' voucher ' || it.voucher,
                                 'zet:ES:' || v_uuid || ':' || it.voucher, 'zet_order', v_uuid::text,
                                 jsonb_build_array(
                                   jsonb_build_object('account_code','4.9.01','side','D','amount_cents',it.net_cents),
                                   jsonb_build_object('account_code','1.2.01','side','C','amount_cents',it.net_cents)));
        end if;
        v_outcome := 'estorno';
      end if;
    end loop;
    select count(*) into v_remaining from sales.zet_order_items where order_uuid = v_uuid and status = 'valid';
    update sales.zet_orders
       set status = case when v_remaining = 0 then 'ESTORNADO' else 'PARCIALMENTE_ESTORNADO' end,
           refunded_at = coalesce(refunded_at, ib.received_at),
           updated_from_inbox = p_id
     where order_uuid = v_uuid and status in ('PAGO','PARCIALMENTE_ESTORNADO');
  end if;

  -- checa o balanceamento agora (e não só no COMMIT do lote): um erro fica preso a este webhook
  set constraints fin.postings_balanced, fin.entries_have_postings immediate;
  set constraints fin.postings_balanced, fin.entries_have_postings deferred;

  update integ.webhook_inbox
     set status = 'processed', processed_at = now(), outcome = v_outcome, last_error = null
   where id = p_id;
  return v_outcome;
end $$;

-- Drena a fila: cada webhook na sua subtransação; erro vira failed com espera crescente; 8 tentativas → dead.
create or replace function integ.process_pending(p_limit int default 100) returns int
language plpgsql security definer set search_path = integ, pg_temp as $$
declare r record; n int := 0; v_err text; v_backoff interval[] :=
  array['1 minute','5 minutes','15 minutes','1 hour','1 hour','4 hours','4 hours','12 hours']::interval[];
begin
  for r in select id, attempts from integ.webhook_inbox
            where status in ('pending','failed') and next_attempt_at <= now()
            order by received_at, id
            limit p_limit
            for update skip locked
  loop
    begin
      perform integ.process_inbox(r.id);
      n := n + 1;
    exception when others then
      get stacked diagnostics v_err = message_text;
      update integ.webhook_inbox
         set status = case when r.attempts + 1 >= 8 then 'dead' else 'failed' end,
             attempts = r.attempts + 1,
             last_error = left(v_err, 1000),
             next_attempt_at = now() + v_backoff[least(r.attempts + 1, 8)]
       where id = r.id;
    end;
  end loop;
  return n;
end $$;

-- ---------- Permissões ----------
alter table integ.webhook_inbox       enable row level security;
alter table integ.zet_event_map       enable row level security;
alter table integ.zet_ticket_type_map enable row level security;
alter table sales.zet_orders          enable row level security;
alter table sales.zet_order_items     enable row level security;
alter table recon.exceptions          enable row level security;

revoke all on all tables in schema integ, sales, recon from public, anon, authenticated;
revoke all on all functions in schema integ, sales, recon, fin from public, anon, authenticated;
revoke update, delete, truncate on integ.webhook_inbox from service_role;
