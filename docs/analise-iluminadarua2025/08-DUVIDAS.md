# Dúvidas e perguntas em aberto

A análise marcou como **[DÚVIDA]** tudo o que o código não permite afirmar. As respostas mudam o plano de contas, os lançamentos-padrão ou a reconstrução.

## Para você (regra de negócio)

1. ~~**Taxa da Zet**~~ **Respondida:** acréscimo de 10% sobre o preço do ingresso, pago pelo cliente e retido pela Zet (R$ 30,00 + R$ 3,00 = R$ 33,00 no payload). A receita do evento é o líquido.
2. ~~**Desconto**~~ **Respondida:** só em campanhas; o `totalValue` já vem com o desconto aplicado.
3. ~~**Estorno Zet (taxa)**~~ **Respondida:** o evento devolve só o preço do ingresso (R$ 30,00); a taxa não afeta o evento. Na bilheteria o estorno é sempre total; no online **pode ser parcial**. *Técnico, para a Zet:* no ES parcial, `eventTicketCodes` traz só os vouchers estornados? E o que vem em `totalValue`/`totalTax`?
4. ~~**Comissão de foods**~~ **Respondida:** a loja paga a comissão ao evento. O repasse é receita do evento.
5. ~~**Ajuste de comissão**~~ **Respondida:** percentual individual por loja, pagamento diário; pagamento a menor é **falta de repasse**, com alerta para pagar no próximo caixa.
6. **Ingressos físicos:** o preço dos cartões inteira, meia e social é fixo por evento/dia? Há venda de produtos em todos os caixas?
7. ~~**Caixa mínimo**~~ **Respondida:** configurado por evento.
8. ~~**Dia operacional**~~ **Respondida:** online vira à meia-noite; bilheteria termina quando o caixa daquele dia é fechado.
9. ~~**Aprovação**~~ **Respondida:** o relatório é assinado por duas pessoas designadas durante o evento, trocáveis a qualquer momento. Depois do fechamento, a sangria vai para conta bancária ou para pagamento de despesas.
9a. ~~**Fundo de troco**~~ **Respondida:** varia por operador; vai junto na sangria e é retirado de novo no início do dia seguinte. Nada fica de um dia para o outro.
10. ~~**Contas bancárias**~~ **Respondida:** cadastradas e alteradas durante o evento, com transferência entre contas. *Observação:* se alguma conta for de pessoa física (o código antigo cita `fabio`), convém registrar o titular para a prestação de contas.

25. ~~Tolerâncias~~ **Respondida:** valores aprovados, editáveis numa tela de configuração do evento.
26. ~~Dinheiro no guichê~~ **Respondida:** no fechamento não fica dinheiro no guichê. Pode haver sangria **durante** o dia; ela é registrada na hora.
27. ~~Maquininhas~~ **Respondida:** uma por guichê. *Próximo passo:* pedir ao PagBank o **token da API do Extrato EDI** (importação automática em D+1) A maioria das maquininhas é Smart: plano em duas etapas (API EDI para todas; depois app em tempo real nas Smart).

## Para a Zet (técnico)

11. ~~Assinatura~~ **Respondida:** a Zet **não assina** os webhooks.
12. O endereço do webhook pode ser configurado com um **token secreto** (no caminho ou num header fixo)? Isso é essencial, já que não há assinatura.
13. Quais são os **IPs de origem** dos webhooks? O histórico não ajuda: o sistema antigo gravou só o IP do Cloudflare. O `user-agent` da Zet é `axios/0.27.2`.
14. Qual é a política de **reenvio** (quantas tentativas, intervalo, o que conta como sucesso)? O backup mostra reenvios (1.256 pedidos com 2 ou mais entregas), mas 72 webhooks que deram erro de conexão nunca chegaram de novo com sucesso.
15. Existe **API de consulta** de pedidos (por período e por uuid) ou só export do painel?
16. Existe relatório de **composição de cada repasse** (quais pedidos entraram)?

## Sobre o incidente

17. ~~O que foi perdido~~ **Respondida:** os payloads de uma data (o dia do apagão da AWS) ficaram corrompidos depois de uma enxurrada de requisições que travou o banco; os valores deixaram de bater com a plataforma.
18. ~~Endpoint~~ **Respondida:** `api.ruailuminada.com`, passando pelo Cloudflare até o banco.
19. Qual é a **data exata** do incidente? (Provavelmente 20/10/2025.)
20. O plano do Cloudflare guarda **logs/analytics** daquele dia? Eles mostram se a enxurrada veio da Zet (reenvios) ou de outros IPs.
21. O sistema antigo ainda está no ar e recebendo webhooks?
22. ~~Início do backup~~ **Respondida:** as vendas começaram em 15/10/2025; os webhooks foram enviados depois. O período 15/10 a 21/10 não está no backup e sai do relatório da Zet.
23. ~~Taxa diferente~~ **Respondida:** a Zet cobrava errado a taxa da meia-entrada e corrigiu depois que o sistema apontou. Vale o valor do relatório e do repasse.
24. ~~Inteira a R$ 50 e R$ 72~~ **Respondida:** sessões de teste com brindes e horário especial, com preço próprio.

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
