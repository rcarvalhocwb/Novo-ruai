-- Invariantes do livro-razão (05-backlog, F-04; 07-plano-de-testes, 7.2).
begin;
set local search_path = extensions, public;
select plan(19);

-- ---------- cenário ----------
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000a1');
insert into fin.events(id, name, starts_on, ends_on)
values ('11111111-1111-1111-1111-111111111111', 'Evento teste', '2026-10-15', '2027-01-10'),
       ('22222222-2222-2222-2222-222222222222', 'Outro evento', '2026-10-15', '2027-01-10');

select is(fin.create_chart_of_accounts('11111111-1111-1111-1111-111111111111'), 29,
          'plano de contas padrão cria 29 contas');
select is(fin.create_chart_of_accounts('11111111-1111-1111-1111-111111111111'), 0,
          'criar o plano de novo é idempotente');
select fin.create_chart_of_accounts('22222222-2222-2222-2222-222222222222');

-- força a checagem dos triggers diferidos (senão só no COMMIT)
create function pg_temp.post(p_key text, p_lines jsonb, p_date date default '2026-10-16') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := fin.post_entry('11111111-1111-1111-1111-111111111111', p_date, now(), 'teste', 'teste',
                      p_key, null, null, p_lines);
  set constraints all immediate;
  set constraints all deferred;
  return v;
end $$;

-- ---------- balanceamento ----------
-- venda Zet: 1 inteira + 1 meia, líquido R$ 54,00
select lives_ok($$ select pg_temp.post('zet:CP:pedido-1',
  '[{"account_code":"1.2.01","side":"D","amount_cents":5400},
    {"account_code":"4.1.01","side":"C","amount_cents":5400}]') $$,
  'lançamento balanceado é aceito');

select throws_ok($$ select pg_temp.post('desbalanceado',
  '[{"account_code":"1.2.01","side":"D","amount_cents":5400},
    {"account_code":"4.1.01","side":"C","amount_cents":5399}]') $$,
  '23514', null, 'lançamento com D ≠ C é rejeitado');

select throws_ok($$ select pg_temp.post('uma-partida',
  '[{"account_code":"1.2.01","side":"D","amount_cents":5400}]') $$,
  '22023', null, 'lançamento com 1 partida é rejeitado');

select throws_ok($$ select pg_temp.post('fracionado',
  '[{"account_code":"1.2.01","side":"D","amount_cents":10.5},
    {"account_code":"4.1.01","side":"C","amount_cents":10.5}]') $$,
  '22023', null, 'centavos não inteiros são rejeitados');

select throws_ok($$ select pg_temp.post('zero',
  '[{"account_code":"1.2.01","side":"D","amount_cents":0},
    {"account_code":"4.1.01","side":"C","amount_cents":0}]') $$,
  '23514', null, 'valor zero é rejeitado');

select throws_ok($$ select pg_temp.post('conta-inexistente',
  '[{"account_code":"9.9.99","side":"D","amount_cents":100},
    {"account_code":"4.1.01","side":"C","amount_cents":100}]') $$,
  '23503', null, 'conta inexistente é rejeitada');

select throws_ok($$
  with e as (insert into fin.journal_entries(event_id, business_date, occurred_at, kind, description, idempotency_key)
             values ('11111111-1111-1111-1111-111111111111', '2026-10-16', now(), 'x', 'x', 'sem-partidas') returning id)
  select 1 from e; set constraints all immediate $$,
  '23514', null, 'lançamento sem partidas é rejeitado no COMMIT');

select throws_ok($$
  with e as (insert into fin.journal_entries(event_id, business_date, occurred_at, kind, description, idempotency_key)
             values ('11111111-1111-1111-1111-111111111111', '2026-10-16', now(), 'x', 'x', 'outro-evento') returning id)
  insert into fin.postings(entry_id, account_id, side, amount_cents)
  select e.id, a.id, s.side, 100 from e,
    (values ('D','1.2.01'),('C','4.1.01')) s(side, code)
    join fin.accounts a on a.code = s.code and a.event_id = '22222222-2222-2222-2222-222222222222';
  set constraints all immediate $$,
  '23514', null, 'partida em conta de outro evento é rejeitada');

-- ---------- idempotência ----------
select is(pg_temp.post('zet:CP:pedido-1',
  '[{"account_code":"1.2.01","side":"D","amount_cents":5400},
    {"account_code":"4.1.01","side":"C","amount_cents":5400}]'),
  (select id from fin.journal_entries where idempotency_key = 'zet:CP:pedido-1'),
  'mesma chave devolve o mesmo lançamento');
select is((select count(*)::int from fin.postings p join fin.journal_entries e on e.id = p.entry_id
            where e.idempotency_key = 'zet:CP:pedido-1'), 2, 'reenvio não duplica partidas');

-- ---------- imutabilidade ----------
select throws_ok($$ update fin.journal_entries set description = 'x' $$, '42501', null, 'UPDATE em lançamentos é proibido');
select throws_ok($$ delete from fin.postings $$, '42501', null, 'DELETE em partidas é proibido');
select throws_ok($$ truncate fin.postings cascade $$, '42501', null, 'TRUNCATE em partidas é proibido');
select throws_ok($$ update fin.accounts set code = '1.2.99' where code = '1.2.01' $$, '42501', null,
                 'código da conta é imutável');

-- ---------- estorno por voucher e saldo ----------
-- estorno só da meia: R$ 18,00
select pg_temp.post('zet:ES:pedido-1:voucher-meia',
  '[{"account_code":"4.9.01","side":"D","amount_cents":1800},
    {"account_code":"1.2.01","side":"C","amount_cents":1800}]');
select is((select balance_cents from fin.v_account_balances
            where event_id = '11111111-1111-1111-1111-111111111111' and code = '1.2.01'),
          3600::bigint, 'A receber Zet = R$ 36,00 depois do estorno da meia');

-- reverse_entry: espelho, idempotente
select is(
  fin.reverse_entry((select id from fin.journal_entries where idempotency_key = 'zet:ES:pedido-1:voucher-meia'),
                    '2026-10-17', 'estorno lançado por engano'),
  fin.reverse_entry((select id from fin.journal_entries where idempotency_key = 'zet:ES:pedido-1:voucher-meia'),
                    '2026-10-17', 'estorno lançado por engano'),
  'estornar duas vezes devolve o mesmo estorno');
select is((select balance_cents from fin.v_account_balances
            where event_id = '11111111-1111-1111-1111-111111111111' and code = '1.2.01'),
          5400::bigint, 'estorno do estorno devolve o saldo a R$ 54,00');

select * from finish();
rollback;
