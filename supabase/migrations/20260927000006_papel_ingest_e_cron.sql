-- Papel técnico do consumidor da fila (Worker zet-consumer via Hyperdrive) e agendamento do processador.
--
-- O papel nasce SEM login e sem senha: a senha nunca entra no repositório. Para ligar, o dono roda no
-- SQL editor do projeto (valor gerado na hora e guardado só no cofre / configuração do Hyperdrive):
--   alter role ingest_writer with login password '<senha forte>';

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'ingest_writer') then
    create role ingest_writer nologin noinherit;
  end if;
end $$;

-- Só pode chamar integ.receive_webhook. Não lê nem escreve tabela nenhuma diretamente.
grant usage on schema integ to ingest_writer;
grant execute on function integ.receive_webhook(text, text, text, jsonb, text, timestamptz) to ingest_writer;
alter role ingest_writer set statement_timeout = '5s';

-- Processador: a cada minuto drena até 200 webhooks (maior dia de 2025: 943 pedidos no dia inteiro).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('zet-process-inbox', '* * * * *', 'select integ.process_pending(200)');
  end if;
end $$;
