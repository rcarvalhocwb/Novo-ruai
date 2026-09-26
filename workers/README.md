# Workers da Cloudflare

| Worker | Papel | Toca o banco? |
|---|---|---|
| `zet-ingest` | Recebe o webhook da Zet em `ingest.ruailuminada.com/zet/v1/<token>`, guarda o corpo cru no R2, enfileira e responde 200 | **Não** |
| `zet-consumer` | Lê a fila, busca o corpo no R2 e chama `integ.receive_webhook` como `ingest_writer` (Hyperdrive) | Só essa função |

O processamento (venda, estorno por voucher, lançamentos) roda **dentro do Postgres**, pelo `pg_cron` a cada minuto (`integ.process_pending`).

## Testes

```bash
pnpm -r test                                   # unitários (sem banco)
RUAI_DB_URL=postgres://... pnpm --filter @ruai/zet-consumer test   # + ponta a ponta com Postgres migrado
```

## Colocar no ar (hml primeiro; produção igual, com `--env production`)

Já feito: buckets R2 `ruai-raw-hml` e `ruai-raw`; migrações 1 a 6 no projeto Supabase Iluminada2026.

Falta (precisa de quem tem acesso à conta Cloudflare e ao Supabase; **nenhum segredo vai para o repositório nem para mensagem**):

1. **Filas:** `wrangler queues create zet-webhooks-hml` e `wrangler queues create zet-webhooks-dlq-hml`; depois configurar retenção máxima (14 dias) nas duas.
2. **Senha do `ingest_writer`:** no SQL editor do Supabase, `alter role ingest_writer with login password '<gerada na hora>';`
3. **Hyperdrive:** `wrangler hyperdrive create ruai-ingest-hml --connection-string "postgres://ingest_writer:<senha>@<host do pooler, modo sessão>:5432/postgres"` e colocar o **id** retornado em `zet-consumer/wrangler.toml` (o id não é segredo).
4. **Token do webhook:** gerar 32 bytes aleatórios em base64url (ex.: `openssl rand -base64 32 | tr '+/' '-_' | tr -d '='`) e cadastrar com `wrangler secret put ZET_URL_TOKEN --env hml`. O mesmo valor vai **só** no link do webhook no painel da Zet.
5. **Deploy:** `pnpm --filter @ruai/zet-ingest deploy:hml` e `pnpm --filter @ruai/zet-consumer deploy:hml` (o domínio `ingest-hml.ruailuminada.com` é criado pelo `custom_domain`).
6. **WAF / rate limit** na zona: só `POST /zet/v1/*` em `ingest.`; limite por IP (ver `docs/plano-execucao/02`).
7. **De-para:** cadastrar em `integ.zet_event_map` o `event.id` da Zet (evento de teste → `source = 'zet_hml'`) e os `eventsValues.id` em `integ.zet_ticket_type_map`.

Automatizar com um token de API da Cloudflare (secret `CLOUDFLARE_API_TOKEN` no GitHub Environment) é o passo seguinte: aí o deploy sai do CI.

## Observações

- Os buckets R2 ficaram com localização ENAM (América do Norte leste); o R2 não oferece região no Brasil. O corpo cru tem dados pessoais do comprador: registrar no inventário LGPD (armazenamento fora do país, com o provedor).
- `zet-consumer` nunca descarta mensagem: banco fora → nova tentativa com espera crescente (até 1 h); depois de 100 tentativas, fila morta `zet-webhooks-dlq*` + alerta. O corpo continua no R2, e a reconciliação R2 × inbox (W-04) recupera.
