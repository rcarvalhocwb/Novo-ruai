# Resumo executivo: análise do `iluminadarua2025`

> Repositório analisado: `iluminadarua/iluminadarua2025` (commit `66d7ba2`, 25/09/2026)
> Stack: React 18 + Vite + Capacitor (front/mobile) e Supabase (Postgres, 111 edge functions, 321 migrations)
> Escopo desta análise: fluxo financeiro (vendas Zet, bilheteria, foods/comissões, fechamentos, conciliação), segurança da integração e integridade dos dados.

## Veredito em uma frase

A **lógica de negócio está certa**: os fluxos de venda, repasse, comissão e fechamento fazem sentido. A **fundação técnica é que não sustenta dinheiro**. Não existe livro-razão imutável, os valores são gravados e recalculados em vários lugares com regras diferentes, qualquer pessoa com a chave pública do app consegue gravar ou apagar dados financeiros, e o que foi apagado não deixa rastro. As divergências e a perda de dados não foram azar: essa arquitetura leva a elas.

## O que está certo (e deve ser preservado)

- Usar **os valores exatos que a Zet envia** (`totalValue`, `totalTax`) em vez de recalcular a taxa (regra já documentada em `docs/architecture/FINANCIAL-CALCULATIONS.md`).
- Ter uma tabela central de vendas Zet com **chave única no `order.uuid`** (`zet_sales_master`) e **valores em centavos (BIGINT)**.
- Gravar o **payload bruto** do webhook (`webhook_logs.payload`, `zet_sales_master.webhook_payload`).
- Ter um fluxo de fechamento diário com **conferência física** (troco, catraca, comissões), **assinatura** e **aprovação em dois níveis**.
- Separar domínios: online (Zet), bilheteria física (dinheiro/cartão PagBank), foods (comissões e repasses), caixa geral e repasse à administração.
- A função `distributeValue` em `_shared/currency-utils.ts` (distribuição de centavos) está correta. Só não é usada onde precisaria.

## Por que cada problema aconteceu

### 1. Centavos divergentes nos fechamentos
Não há uma única causa: são **cinco mecanismos somados**.

| # | Mecanismo | Exemplo concreto |
|---|-----------|------------------|
| 1 | Mesma comissão calculada de **3 jeitos** diferentes | `R$ 1.234,56 × 15%` vira `185.184` (sem arredondar, `StoreDailySalesManager.tsx:198`) e `185.18` (arredondado, `EditClosureDialog.tsx:55`). Basta editar um fechamento para a soma mudar. |
| 2 | Arredondamento com `Math.round(x*100)/100` em float | `roundCurrency(1.005)` devolve `1.00` em vez de `1.01`, e `Math.round(1.255*100)` devolve `125` em vez de `126`. |
| 3 | Rateio da venda Zet **por quantidade**, e não por preço | Pedido com 1 inteira (R$ 20) e 1 meia (R$ 10), total R$ 30: o sistema grava R$ 15 + R$ 15 (`comprenozet-webhook/index.ts:1277`). |
| 4 | **Fronteira de dia em UTC** em vez de horário de Brasília | 66 consultas usam `T00:00:00` sem fuso e 63 usam `toISOString().split('T')[0]`. Uma venda às 21h30 (BRT) cai no dia seguinte, e cada tela a coloca num dia diferente. |
| 5 | **Limite silencioso de 1.000 linhas** do Supabase | 187 consultas somam no navegador sem paginar. Passou de 1.000 vendas no período, o total fica menor sem nenhum erro. |

Além disso, dois documentos do próprio repositório **se contradizem sobre a taxa da Zet**: um diz "10% sobre o bruto", o outro diz "markup de 10% sobre o líquido" (ver `02-RELATORIO-DE-PROBLEMAS.md`, P-04). Funções de "correção" (`recalculate-zet-taxes`, `fix-comprenozet-tax-calculation`) reescreveram taxas com base nessas regras conflitantes.

### 2. Ataque na API da Zet, queda e perda de dados
- O webhook v1 roda em **modo permissivo** (aceita vendas **sem assinatura**, conforme `docs/integrations/COMPRENOZET-INTEGRATION.md`), e o **webhook v2 não tem validação de assinatura nenhuma**. Qualquer pessoa na internet consegue criar vendas falsas ou marcar vendas reais como ESTORNADO.
- Cada requisição dispara **cerca de 46 operações no banco**, sem limite de tamanho do corpo, sem rate limit e com um `sleep` de 2 s em caso de concorrência. Cada requisição do atacante vira dezenas de escritas: amplificação perfeita para derrubar o banco.
- **Pelo menos 81 das 111 edge functions não verificam o papel do usuário** e usam a `service_role` (acesso total). `verify_jwt = true` **não protege**, porque a chave anônima pública que está no front-end é um JWT válido. Entre elas:
  - `reset-comprenozet-online-sales` apaga todas as vendas Zet de um período;
  - `cleanup-test-events` (`verify_jwt = false`) apaga as validações e os acessos do dia;
  - `r2-backup` (`verify_jwt = false`) **lista, gera link de download e apaga os backups**, que contêm CPF, e-mail e telefone dos clientes.
- Políticas RLS com `USING (true)` **sem `TO`** valem também para o papel **anônimo**: `bank_transactions` (SELECT, INSERT, UPDATE, **DELETE**), `zet_sales_master` (INSERT, UPDATE) e `webhook_logs` (UPDATE, ou seja, dá para apagar a evidência).
- **Cascatas destrutivas**: apagar um evento ou uma loja pela tela de admin apaga em cascata fechamentos, vendas de lojas, repasses, movimentos de caixa e vendas online.
- **O rascunho do fechamento sobrescreve o fechamento finalizado**: o auto-save faz `upsert` em `(event_id, closure_date)` com `status = 'draft'` e totais zerados, sem checar se já existe um fechamento aprovado.
- **Backups insuficientes**: `system-backup` não salva nada (o código diz "Simular salvamento"), e `r2-backup` corta cada tabela em 10.000 linhas e não inclui `webhook_logs`, `bank_transactions`, `daily_closures`, `food_repayments` nem `store_cash_movements`.
- Migrations e rotinas **apagaram `webhook_logs`**, que era a prova bruta das vendas (`20251009010046`, `20251015230809`).

### 3. Impossível conciliar
- Não existe **livro-razão de partidas dobradas**. Os saldos são "fotos" gravadas (`daily_closures.final_balance`, JSON em `daily_closures_v2`) e editáveis.
- **Nenhuma tabela financeira tem trilha de auditoria** no banco. Só `user_roles`, `user_permissions` e `api_tokens` têm trigger de auditoria.
- As correções foram feitas com `UPDATE` e `DELETE` diretos, que **destroem o valor anterior** (ver `docs/FINANCIAL-CORRECTIONS-LOG.md`).
- O navegador grava e apaga direto em `daily_closures`, `store_daily_sales`, `bank_transactions`, `order_items`, `online_transfers` e `imported_pagbank_transactions`.

## O que muda na reconstrução (princípios)

1. **Dinheiro = inteiro em centavos**, com um único tipo `Money` e uma única política de arredondamento (meio-para-cima, com decimal exato, nunca float).
2. **Livro-razão de partidas dobradas, append-only**: nada é editado nem apagado; correção é estorno mais novo lançamento. O banco garante `Σ débitos = Σ créditos`.
3. **Saldos e fechamentos são derivados do livro-razão**, e o fechamento **trava o período**.
4. **Webhook = caixa de entrada**: grava o corpo cru, valida HMAC com timestamp, responde 200 rápido e processa de forma assíncrona e idempotente, com máquina de estados.
5. **Conciliação em três pontas** (sistema × Zet × extrato bancário), com fila de exceções.
6. **Menor privilégio**: o navegador nunca escreve em tabela financeira. As escritas passam só por funções no servidor com checagem de papel. O usuário da aplicação não tem `DELETE`, `TRUNCATE` nem `DROP`.
7. **Backup de verdade**: PITR ativado, dump diário completo fora do Supabase, restauração testada todo mês.

## Ações urgentes no sistema ATUAL (se ele ainda estiver no ar)

1. Desativar ou exigir papel de admin em `r2-backup`, `reset-comprenozet-online-sales`, `cleanup-test-events`, `cleanup-*`, `fix-*`, `reprocess-*`, `recalculate-*`, `migrate-*` e `remove-phantom-order`.
2. Trocar as políticas `USING (true)` de `bank_transactions`, `zet_sales_master` e `webhook_logs` por `TO service_role` (ou por uma checagem de admin).
3. `WEBHOOK_SIGNATURE_ENFORCEMENT=strict` e desativar o `comprenozet-webhook-v2`.
4. Rotacionar `WEBHOOK_SECRET`, as chaves do R2 e a `service_role`.
5. **Baixar agora** todos os backups do R2 e um `pg_dump` completo, e guardar fora do Supabase (é matéria-prima da recuperação).

## Documentos desta análise

| Arquivo | Conteúdo |
|---------|----------|
| `01-LOGICA-DE-NEGOCIO.md` | Regras e fluxos a preservar, glossário e diagramas |
| `02-RELATORIO-DE-PROBLEMAS.md` | Tabela de problemas com severidade, arquivo:linha e correção |
| `03-ARQUITETURA-ALVO.md` | Arquitetura recomendada, DDL do livro-razão, tipo `Money` e rateio |
| `04-INTEGRACAO-ZET.md` | Especificação da integração Zet (segurança, idempotência, falhas) |
| `05-MIGRACAO-E-RECUPERACAO.md` | Como reconstruir e conciliar o histórico perdido |
| `06-ROADMAP.md` | Fases de reconstrução com critérios de aceite |
| `07-CHECKLISTS.md` | Checklist de fechamento financeiro e de segurança para produção |
| `08-DUVIDAS.md` | Perguntas que só você pode responder |
