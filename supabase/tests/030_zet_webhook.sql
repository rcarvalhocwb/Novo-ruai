-- Webhook da Zet: inbox imutável, máquina de estados por voucher, exceções (W-02, W-03; 07-plano-de-testes, 7.2).
begin;
set local search_path = extensions, public;
select plan(39);

insert into fin.events(id, name, starts_on, ends_on)
values ('11111111-1111-1111-1111-111111111111', 'Evento teste', '2026-10-15', '2027-01-10');
select fin.create_chart_of_accounts('11111111-1111-1111-1111-111111111111');
insert into integ.zet_event_map(zet_event_id, source, event_id) values (900, 'zet', '11111111-1111-1111-1111-111111111111');
insert into integ.zet_ticket_type_map(zet_events_value_id, zet_event_id, description, category, list_price_cents) values
  (1, 900, 'Inteira', 'inteira', 3600),
  (2, 900, 'Meia-entrada', 'meia', 1800),
  (3, 900, 'Cortesia', 'cortesia', 0);

-- recebe um corpo como o consumidor da fila faria (base64 + sha256)
create function pg_temp.recv(p_body jsonb) returns bigint language sql as $$
  select integ.receive_webhook('zet', encode(convert_to(p_body::text, 'UTF8'), 'base64'),
                               encode(sha256(convert_to(p_body::text, 'UTF8')), 'hex'),
                               '{"user-agent":"axios/0.27.2"}', '203.0.113.10', now())
$$;
-- monta um payload no formato da Zet (sem nome, CPF, e-mail ou telefone)
create function pg_temp.zet(p_action text, p_uuid text, p_total numeric, p_tax numeric, p_vouchers jsonb,
                            p_paid text default '2026-10-16T15:00:00Z', p_event int default 900, p_extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('action', p_action, 'data', jsonb_build_object(
    'order', jsonb_build_object('id', 198284, 'uuid', p_uuid, 'paymentType', 'PIX',
                                'paymentSituation', case p_action when 'CP' then 'PAGO' else 'ESTORNADO' end,
                                'paymentConfirmeDate', p_paid, 'createdAt', p_paid,
                                'totalValue', p_total, 'totalTax', p_tax, 'discount', 0) || p_extra,
    'eventTicketCodes', (select jsonb_agg(jsonb_build_object('voucher', v->>0,
                            'eventsValues', jsonb_build_object('id', (v->>1)::int, 'session', '19h',
                               'eventsDates', jsonb_build_object('startDate', '2026-10-20T21:00:00Z'))))
                         from jsonb_array_elements(p_vouchers) v),
    'event', jsonb_build_object('id', p_event)))
$$;
create function pg_temp.saldo(p_code text) returns bigint language sql as $$
  select balance_cents from fin.v_account_balances
   where event_id = '11111111-1111-1111-1111-111111111111' and code = p_code
$$;
create function pg_temp.run(p_id bigint) returns text language plpgsql as $$
declare r text; begin r := integ.process_inbox(p_id); set constraints all immediate; set constraints all deferred; return r; end $$;

-- ---------- rateio em SQL = rateio do money.ts ----------
select is(fin.allocate(3000, array[2000,1000]::bigint[]), array[2000,1000]::bigint[], 'allocate: inteira + meia');
select is(fin.allocate(1000, array[1,1,1]::bigint[]), array[334,333,333]::bigint[], 'allocate: maior resto');
select is(integ.to_cents_strict('39.6'::jsonb), 3960::bigint, 'to_cents_strict: 39.6 → 3960');
select throws_ok($$ select integ.to_cents_strict('33.333'::jsonb) $$, '22023', null, 'to_cents_strict: 3 casas é rejeitado');

-- ---------- inbox ----------
select is(pg_temp.recv(pg_temp.zet('CP','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40, '[["V-INT-1",1],["V-MEIA-1",2]]')),
          pg_temp.recv(pg_temp.zet('CP','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40, '[["V-INT-1",1],["V-MEIA-1",2]]')),
          'mesmo corpo 2× → mesma linha do inbox');
select is((select count(*)::int from integ.webhook_inbox), 1, 'reenvio idêntico não cria linha');
select throws_ok($$ select integ.receive_webhook('zet', encode('{}'::bytea, 'base64'), repeat('0', 64), '{}', null, now()) $$,
                 '22023', null, 'sha256 que não confere é rejeitado');
select throws_ok($$ update integ.webhook_inbox set raw_body = 'x' $$, '42501', null, 'corpo do webhook é imutável');
select throws_ok($$ delete from integ.webhook_inbox $$, '42501', null, 'inbox não pode ser apagado');

-- ---------- CP: 1 inteira + 1 meia, bruto 59,40, taxa 5,40 → líquido 54,00 ----------
select is(pg_temp.run((select max(id) from integ.webhook_inbox)), 'venda', 'CP novo vira venda');
select is((select status from sales.zet_orders where order_uuid = 'aaaaaaaa-0000-0000-0000-000000000001'), 'PAGO', 'pedido PAGO');
select is((select net_cents from sales.zet_order_items where voucher = 'V-INT-1'), 3600::bigint, 'inteira rateada em R$ 36,00');
select is((select net_cents from sales.zet_order_items where voucher = 'V-MEIA-1'), 1800::bigint, 'meia rateada em R$ 18,00');
select is(pg_temp.saldo('1.2.01'), 5400::bigint, 'A receber Zet = R$ 54,00');
select is(pg_temp.saldo('4.1.01'), 5400::bigint, 'receita online = líquido (a taxa é da Zet)');
select is((select visit_date from sales.zet_order_items where voucher = 'V-INT-1'), '2026-10-20'::date, 'data da visita gravada separada');

-- mesmo pedido, corpo diferente (campo extra) e mesmos valores → nada muda
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('CP','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40,
            '[["V-INT-1",1],["V-MEIA-1",2]]', p_extra => '{"webHookTermsAccepted":true}'))),
          'venda_repetida', 'CP repetido com os mesmos valores é no-op');
select is(pg_temp.saldo('1.2.01'), 5400::bigint, 'reenvio não duplica lançamento');

-- mesmo pedido com valor diferente → exceção, nunca sobrescreve
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('CP','aaaaaaaa-0000-0000-0000-000000000001', 99.00, 9.00,
            '[["V-INT-1",1],["V-MEIA-1",2]]'))), 'excecao', 'CP com valor diferente vira exceção');
select is((select gross_cents from sales.zet_orders where order_uuid = 'aaaaaaaa-0000-0000-0000-000000000001'),
          5940::bigint, 'o primeiro CP válido continua valendo');
select ok(exists(select 1 from recon.exceptions where kind = 'amount_mismatch'), 'exceção amount_mismatch aberta');

-- ---------- ES parcial: só a meia ----------
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('ES','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40, '[["V-MEIA-1",2]]'))),
          'estorno', 'ES parcial processado');
select is((select status from sales.zet_orders where order_uuid = 'aaaaaaaa-0000-0000-0000-000000000001'),
          'PARCIALMENTE_ESTORNADO', 'pedido parcialmente estornado');
select is((select status from sales.zet_order_items where voucher = 'V-INT-1'), 'valid', 'a inteira continua válida');
select is(pg_temp.saldo('1.2.01'), 3600::bigint, 'estorno devolve só o preço da meia: saldo R$ 36,00');
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('ES','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40, '[["V-MEIA-1",2]]',
            p_extra => '{"reenvio":1}'))), 'estorno_repetido', 'ES repetido é no-op');
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('ES','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40, '[["V-INT-1",1]]'))),
          'estorno', 'ES do restante');
select is((select status from sales.zet_orders where order_uuid = 'aaaaaaaa-0000-0000-0000-000000000001'),
          'ESTORNADO', 'pedido totalmente estornado');
select is(pg_temp.saldo('1.2.01'), 0::bigint, 'A receber Zet zerado');

-- CP atrasado depois do ES: não reverte, abre exceção
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('CP','aaaaaaaa-0000-0000-0000-000000000001', 59.40, 5.40,
            '[["V-INT-1",1],["V-MEIA-1",2]]', p_extra => '{"atrasado":true}'))), 'venda_repetida', 'CP depois de ES não reverte');
select ok(exists(select 1 from recon.exceptions where kind = 'cp_apos_es'), 'exceção cp_apos_es aberta');

-- ---------- ES antes do CP (órfão) e nova tentativa ----------
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('ES','bbbbbbbb-0000-0000-0000-000000000002', 39.60, 3.60, '[["V-INT-2",1]]'))),
          'estorno_orfao', 'ES sem CP fica em espera');
select pg_temp.run(pg_temp.recv(pg_temp.zet('CP','bbbbbbbb-0000-0000-0000-000000000002', 39.60, 3.60, '[["V-INT-2",1]]')));
update integ.webhook_inbox set next_attempt_at = now() where status = 'failed';
select integ.process_pending(10);
select is((select status from sales.zet_orders where order_uuid = 'bbbbbbbb-0000-0000-0000-000000000002'),
          'ESTORNADO', 'ES órfão é aplicado quando o CP chega');

-- ---------- falhas que não perdem nada ----------
select pg_temp.recv(pg_temp.zet('CP','cccccccc-0000-0000-0000-000000000003', 39.60, 3.60, '[["V-X",1]]', p_event => 777));
select integ.process_pending(10);
select alike((select last_error from integ.webhook_inbox where status = 'failed' order by id desc limit 1),
            '%sem mapeamento%', 'evento sem de-para fica failed, com o motivo, para reprocessar');

-- taxa fora de 10%: exceção, mas a venda entra (o dinheiro é certo)
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('CP','dddddddd-0000-0000-0000-000000000004', 40.00, 4.00, '[["V-INT-4",1]]'))),
          'venda', 'taxa divergente não bloqueia a venda');
select ok(exists(select 1 from recon.exceptions where kind = 'taxa_divergente' and ref = 'dddddddd-0000-0000-0000-000000000004'),
          'exceção taxa_divergente aberta');

-- cortesia: conta como ingresso, sem lançamento
select is(pg_temp.run(pg_temp.recv(pg_temp.zet('CP','eeeeeeee-0000-0000-0000-000000000005', 0, 0, '[["V-CORT-5",3]]'))),
          'venda', 'cortesia é registrada');
select ok(not exists(select 1 from fin.journal_entries where idempotency_key = 'zet:CP:eeeeeeee-0000-0000-0000-000000000005'),
          'cortesia não gera lançamento');

-- dia operacional em America/Sao_Paulo: 01:10Z de 17/10 = 22:10 de 16/10
select pg_temp.run(pg_temp.recv(pg_temp.zet('CP','ffffffff-0000-0000-0000-000000000006', 39.60, 3.60, '[["V-INT-6",1]]',
                                            p_paid => '2026-10-17T01:10:00Z')));
select is((select business_date from sales.zet_orders where order_uuid = 'ffffffff-0000-0000-0000-000000000006'),
          '2026-10-16'::date, 'venda às 22:10 BRT pertence ao dia 16');

select * from finish();
rollback;
