-- Assinaturas, fechamento, reabertura e separação de funções (F-04, F-05).
begin;
set local search_path = extensions, public;
select plan(17);

insert into auth.users(id) values
  ('00000000-0000-0000-0000-00000000ad01'),  -- admin
  ('00000000-0000-0000-0000-00000000ad02'),  -- admin 2 (reabre)
  ('00000000-0000-0000-0000-00000000a001'),  -- aprovador 1
  ('00000000-0000-0000-0000-00000000a002'),  -- aprovador 2
  ('00000000-0000-0000-0000-00000000a003'),  -- aprovador 3 (não designado)
  ('00000000-0000-0000-0000-00000000c001');  -- operador
insert into fin.events(id, name, starts_on, ends_on)
values ('11111111-1111-1111-1111-111111111111', 'Evento teste', '2026-10-15', '2027-01-10');
select fin.create_chart_of_accounts('11111111-1111-1111-1111-111111111111');
insert into fin.user_roles(event_id, user_id, role) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000ad01', 'admin'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000ad02', 'admin'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a001', 'aprovador'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a002', 'aprovador'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a003', 'aprovador'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000c001', 'operador_caixa');

-- age como um usuário: claims do JWT + papel authenticated
create function pg_temp.as_user(p_user text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'aal', p_aal)::text, true);
$$;
-- lançamento feito "por" alguém (created_by = auth.uid())
create function pg_temp.post(p_key text, p_cents bigint, p_date date default '2026-10-16') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := fin.post_entry('11111111-1111-1111-1111-111111111111', p_date, now(), 'teste', 'teste', p_key, null, null,
         jsonb_build_array(jsonb_build_object('account_code','1.1.00','side','D','amount_cents',p_cents),
                           jsonb_build_object('account_code','4.1.02','side','C','amount_cents',p_cents)));
  set constraints all immediate; set constraints all deferred;
  return v;
end $$;

-- lançamento do dia feito pelo operador
select pg_temp.as_user('00000000-0000-0000-0000-00000000c001');
select pg_temp.post('venda-1', 225000);

-- anon não executa nada
set local role anon;
select throws_ok($$ select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$,
                 '42501', null, 'anon não executa RPC');
reset role;

-- designação
select pg_temp.as_user('00000000-0000-0000-0000-00000000ad01');
set local role authenticated;
select lives_ok($$ select api.designate_signer('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a001') $$,
                'admin designa o 1º assinante');
select lives_ok($$ select api.designate_signer('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a002') $$,
                'admin designa o 2º assinante');
select throws_ok($$ select api.designate_signer('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a003') $$,
                 '23514', null, 'não há 3º assinante vigente');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000ad01', 'aal1');
set local role authenticated;
select throws_ok($$ select api.designate_signer('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000a003') $$,
                 '42501', null, 'admin sem MFA (aal1) é recusado');
reset role;

-- operador não lê saldos
select pg_temp.as_user('00000000-0000-0000-0000-00000000c001', 'aal1');
set local role authenticated;
select throws_ok($$ select * from api.account_balances('11111111-1111-1111-1111-111111111111') $$,
                 '42501', null, 'operador não lê saldos do evento');
select throws_ok($$ select * from fin.journal_entries $$, '42501', null, 'cliente não lê tabelas do fin diretamente');
reset role;

-- assinaturas
select pg_temp.as_user('00000000-0000-0000-0000-00000000a003');
set local role authenticated;
select throws_ok($$ select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$,
                 '42501', null, 'aprovador não designado não assina');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a001');
set local role authenticated;
select lives_ok($$ select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$, '1º assinante assina');
select throws_ok($$ select api.close_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$,
                 '55000', null, 'uma assinatura só não fecha o dia');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a002');
set local role authenticated;
select lives_ok($$ select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$, '2º assinante assina');
reset role;

-- lançamento depois das assinaturas invalida o hash
select pg_temp.as_user('00000000-0000-0000-0000-00000000c001');
select pg_temp.post('venda-atrasada', 100);
select pg_temp.as_user('00000000-0000-0000-0000-00000000a002');
set local role authenticated;
select throws_ok($$ select api.close_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$,
                 '55000', null, 'lançamento novo depois da assinatura exige assinar de novo');
select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000a001');
set local role authenticated;
select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-16');
select lives_ok($$ select api.close_day('11111111-1111-1111-1111-111111111111', '2026-10-16') $$,
                'duas assinaturas sobre o conteúdo atual fecham o dia');
reset role;

-- dia fechado não aceita lançamento
select throws_ok($$ select pg_temp.post('venda-em-dia-fechado', 100) $$, '55000', null,
                 'dia fechado rejeita lançamento');

-- separação: quem lançou no dia não assina
select pg_temp.as_user('00000000-0000-0000-0000-00000000a001');
select pg_temp.post('lancado-pelo-aprovador', 100, '2026-10-17');
set local role authenticated;
select throws_ok($$ select api.sign_day('11111111-1111-1111-1111-111111111111', '2026-10-17') $$,
                 '42501', null, 'quem lançou no dia não assina o dia');
reset role;

-- reabertura: admin com motivo; motivo curto é recusado
select pg_temp.as_user('00000000-0000-0000-0000-00000000ad02');
set local role authenticated;
select throws_ok($$ select api.reopen_day('11111111-1111-1111-1111-111111111111', '2026-10-16', 'erro') $$,
                 '23514', null, 'reabrir exige motivo com pelo menos 10 caracteres');
select lives_ok($$ select api.reopen_day('11111111-1111-1111-1111-111111111111', '2026-10-16',
                                         'depósito lançado na conta errada') $$,
                'admin reabre com motivo, e fica registrado');
reset role;

select * from finish();
rollback;
