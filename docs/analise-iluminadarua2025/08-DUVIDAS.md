# Dúvidas e perguntas em aberto

A análise marcou como **[DÚVIDA]** tudo o que o código não permite afirmar. As respostas mudam o plano de contas, os lançamentos-padrão ou a reconstrução.

## Para você (regra de negócio)

1. ~~**Taxa da Zet**~~ **Respondida:** acréscimo de 10% sobre o preço do ingresso, pago pelo cliente e retido pela Zet (R$ 30,00 + R$ 3,00 = R$ 33,00 no payload). A receita do evento é o líquido.
2. **Desconto:** `totalValue` já vem com o desconto aplicado? O webhook antigo grava `total_amount = totalValue − discount`, mas `gross_amount = totalValue`.
3. **Estorno Zet:** no estorno, o evento devolve só o preço do ingresso (R$ 30,00) ou a Zet também desconta a taxa (R$ 3,00) do repasse do evento? Existe estorno **parcial** (só alguns ingressos do pedido)?
4. ~~**Comissão de foods**~~ **Respondida:** a loja paga a comissão ao evento. O repasse é receita do evento.
5. **Ajuste de comissão:** o wizard permite receber um valor menor que o esperado ("desconto acordado"). Isso é **desconto concedido** (despesa) ou **perda**? Quem pode autorizar?
6. **Ingressos físicos:** o preço dos cartões inteira, meia e social é fixo por evento/dia? Há venda de produtos em todos os caixas?
7. **Caixa mínimo:** R$ 1.000 é regra fixa ou configurável por evento?
8. **Dia operacional:** o evento passa da meia-noite? Se sim, a venda às 00:30 pertence ao dia anterior (dia operacional) ou ao dia civil?
9. **Aprovação:** quem fecha e quem aprova podem ser a mesma pessoa em algum caso?
10. **Contas bancárias:** o código cita `principal` e `fabio` (`fabio_transactions`). Quais contas existem, e alguma é pessoal?

## Para a Zet (técnico)

11. A assinatura HMAC é enviada **sempre**? Qual header, algoritmo e formato (hex ou base64)? É calculada sobre o corpo cru?
12. Há **timestamp** ou **id de entrega** no webhook (para proteção contra replay)?
13. Qual é a política de **reenvio** (quantas tentativas, intervalo, o que conta como sucesso: 2xx)?
14. A ordem CP → ES é garantida?
15. Quais são os **IPs de origem** dos webhooks?
16. Existe **API de consulta** de pedidos (por período e por uuid) ou só export do painel?
17. Existe relatório de **composição de cada repasse** (quais pedidos entraram)?

## Sobre o incidente

18. Quais dados exatamente foram apagados (tabelas e período)? Isso permite casar com os logs das funções e descobrir o vetor (S-01 a S-07, S-11, S-14).
19. Qual endpoint estava configurado no painel da Zet: `comprenozet-webhook` (v1, modo permissivo) ou `comprenozet-webhook-v2` (sem assinatura)?
20. Qual era o plano do Supabase na época (Free/Pro) e se o PITR estava ativo.
21. O sistema antigo ainda está no ar e recebendo webhooks?

---

## Anexo A: edge functions sem checagem de papel

Critério: o arquivo não contém `getUser`, `user_roles`, `has_role`, verificação de assinatura, API key nem segredo de cron. Todas usam a `service_role`. `verify_jwt=true` **não** impede a chamada com a chave anônima pública. "Escritas" = quantidade de chamadas `.insert/.update/.upsert/.delete` no arquivo.

A lista é um **piso**: a heurística é textual. O `r2-backup` (S-01), por exemplo, não aparece porque cita `user_roles` como tabela a copiar, e mesmo assim não tem autenticação nenhuma.

| Função | verify_jwt | Escritas |
|--------|-----------|----------|
| `advanced-analytics` | true (padrão) | 1 |
| `ai-work-history-import` | true | 0 |
| `analyze-middleware-log` | false | 0 |
| `audit-comprenozet-data` | true (padrão) | 0 |
| `audit-spreadsheet-vs-database` | true (padrão) | 0 |
| `auto-checkout-cron` | false | 2 |
| `backfill-online-sales-from-orders` | true (padrão) | 6 |
| `backfill-transactions` | true (padrão) | 1 |
| `cash-closure-assistant` | true | 0 |
| `check-events-integrity` | false | 2 |
| `check-geofence` | true | 6 |
| `cleanup-duplicate-sales-v2` | true | 1 |
| `cleanup-expired-pdfs` | true | 1 |
| `cleanup-test-data` | true (padrão) | 1 |
| `cleanup-test-events` | false | 4 |
| `completar-fase-0` | true (padrão) | 3 |
| `comprenozet-webhook-v2` | false | 4 |
| `create-pagseguro-payment` | true | 1 |
| `expire-pending-orders` | true (padrão) | 1 |
| `fetch-pagseguro-sales` | true | 1 |
| `fetch-weather` | true (padrão) | 0 |
| `fix-comprenozet-tax-calculation` | true (padrão) | 2 |
| `fix-event-session-dates` | true (padrão) | 3 |
| `fix-financial-discrepancies` | true (padrão) | 1 |
| `fix-incorrect-order-values` | true (padrão) | 1 |
| `get-daily-closure-data` | true (padrão) | 0 |
| `import-comprenozet-history` | true (padrão) | 6 |
| `import-comprenozet-spreadsheet` | true (padrão) | 4 |
| `import-missing-zet-sales` | true | 1 |
| `import-zet-refunds` | true | 1 |
| `import-zet-sales-bulk` | true | 1 |
| `log-security-event` | true (padrão) | 1 |
| `middleware-connection-health` | false | 0 |
| `middleware-heartbeat` | false | 8 |
| `middleware-log-error` | false | 4 |
| `middleware-sync-cards` | false | 1 |
| `middleware-sync-events` | false | 5 |
| `migrate-missing-sales` | true | 1 |
| `mobile-ai-assistant` | true | 0 |
| `ocr-card-machine` | true | 0 |
| `ocr-comprenoze` | true | 0 |
| `ocr-pagbank-receipt` | true (padrão) | 1 |
| `parse-bank-statement` | true | 1 |
| `process-payment-confirmation` | true (padrão) | 4 |
| `process-remote-checkout` | false | 3 |
| `processar-eventos-pendentes` | true (padrão) | 0 |
| `profile-assistant` | true | 0 |
| `r2-storage` | true | 0 |
| `realtime-notifications` | true | 3 |
| `recalculate-zet-taxes` | true | 1 |
| `remove-phantom-order` | true (padrão) | 2 |
| `reprocess-closure-pdfs` | true | 1 |
| `reprocess-comprenozet-sales` | true | 12 |
| `reprocess-failed-webhooks` | true (padrão) | 3 |
| `reprocess-historical-webhooks` | true (padrão) | 4 |
| `reprocess-missing-transactions` | true (padrão) | 1 |
| `reprocess-pending-webhooks` | true | 1 |
| `resend-communication` | true | 4 |
| `reset-comprenozet-online-sales` | true (padrão) | 3 |
| `send-geofence-alert` | false | 3 |
| `send-purchase-email` | false | 0 |
| `send-shift-alert` | false | 5 |
| `send-staff-approval-notification` | false | 0 |
| `send-staff-invitation` | false | 0 |
| `send-staff-registration-confirmation` | false | 0 |
| `send-staff-rejection-notification` | false | 0 |
| `send-welcome-email` | false | 0 |
| `shift-alerts-cron` | false | 0 |
| `sync-pdf-to-closure` | true | 1 |
| `sync-zet-sales-master` | true | 1 |
| `terminal-hardware-status` | true (padrão) | 2 |
| `terminal-heartbeat` | true (padrão) | 3 |
| `terminal-payment` | true (padrão) | 1 |
| `terminal-print-ticket` | true (padrão) | 1 |
| `test-brevo-email` | true | 0 |
| `test-communication` | true | 2 |
| `validate-dual-write` | true (padrão) | 1 |
| `validate-financial-data` | true (padrão) | 1 |
| `validate-financial-integrity` | true | 0 |
| `verificar-transacoes-faltantes` | true (padrão) | 0 |
| `webhook-health-check` | true (padrão) | 0 |
