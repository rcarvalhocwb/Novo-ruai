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

Além disso, dois documentos do próprio repositório **se contradiziam sobre a taxa da Zet**. A regra confirmada é: **a taxa é um acréscimo de 10% sobre o preço do ingresso, pago pelo cliente e retido pela Zet** (ingresso R$ 30,00 + taxa R$ 3,00 = R$ 33,00 no payload). O documento `FINANCIAL-CALCULATIONS.md` tratava a taxa como 10% do bruto; por isso achava que a Zet cobrava "a mais" (as taxas de 9,09% do bruto são exatamente 10% do líquido). Além disso, o fechamento diário soma o **bruto** na divisão por forma de pagamento e o **líquido** na divisão por tipo de ingresso, então as duas não batem entre si (ver P-04 e P-15 em `02-RELATORIO-DE-PROBLEMAS.md`).

### 2. Queda da integração Zet e perda de dados
**O que aconteceu** (seu relato + código): no dia do apagão da AWS (provavelmente 20/10/2025), o banco ficou fora. O webhook em `api.ruailuminada.com` (Cloudflare → Supabase) **dependia do banco para responder**. Quando tudo voltou, chegou uma enxurrada de requisições (muito provavelmente os reenvios acumulados da Zet), o banco travou, as vendas ficaram gravadas pela metade, os reenvios sobrescreveram registros e somaram estornos em dobro. Os payloads daquela data ficaram corrompidos e os valores deixaram de bater com a plataforma. A reconstituição passo a passo está em `04-INTEGRACAO-ZET.md`, seção 9.

**O que o backup de webhooks mostrou** (`09-ANALISE-WEBHOOKS-ZET.md`): de 22/10/2025 a 04/01/2026, a Zet mandou 26.111 pedidos (R$ 2.067.707,50 líquidos) com valores **sempre consistentes**. A taxa é exatamente 10% do líquido em 26.109 pedidos, e os reenvios nunca mudaram valores. **O erro estava no processamento, não nos dados da Zet.** Além disso, **199 vendas pagas (R$ 24.313,00 líquidos) nunca foram gravadas** pelo sistema antigo, recusadas por CPF ou e-mail ou perdidas quando o banco caiu. Os payloads estão íntegros e podem ser recuperados. A "assinatura" era gerada pelo nosso próprio Worker para qualquer requisição (e nunca bateu), e o IP gravado era sempre o do Cloudflare.

Os fatores do código que transformaram uma queda de infraestrutura em perda de dados:
- **A Zet não assina os webhooks** (confirmado). O v1 aceitava tudo em modo permissivo e o **v2 não tinha validação nenhuma**. Qualquer pessoa que descobrisse o endereço podia criar vendas falsas ou marcar vendas reais como ESTORNADO.
- Cada requisição dispara **cerca de 46 operações no banco**, sem transação, sem limite de tamanho do corpo, sem rate limit e com um `sleep` de 2 s em caso de concorrência. Um pico de reenvios (ou de ataque) vira dezenas de escritas por requisição: amplificação perfeita para travar o banco.
- Reenvios **sobrescrevem** vendas (upsert sem proteção), estornos são somados de novo, e o **estorno parcial é tratado como total** (P-18).
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
4. **Webhook = caixa de entrada na borda**: como a Zet não assina, a origem é provada por token secreto no endereço e IPs no WAF. O corpo cru é guardado **na borda (Cloudflare), sem depender do banco**, e processado depois, de forma idempotente, com máquina de estados e estorno por ingresso.
5. **Conciliação em três pontas** (sistema × Zet × extrato bancário), com fila de exceções.
6. **Menor privilégio**: o navegador nunca escreve em tabela financeira. As escritas passam só por funções no servidor com checagem de papel. O usuário da aplicação não tem `DELETE`, `TRUNCATE` nem `DROP`.
7. **Backup de verdade**: PITR ativado, dump diário completo fora do Supabase, restauração testada todo mês.

## Ações urgentes no sistema ATUAL (se ele ainda estiver no ar)

1. Desativar ou exigir papel de admin em `r2-backup`, `reset-comprenozet-online-sales`, `cleanup-test-events`, `cleanup-*`, `fix-*`, `reprocess-*`, `recalculate-*`, `migrate-*` e `remove-phantom-order`.
2. Trocar as políticas `USING (true)` de `bank_transactions`, `zet_sales_master` e `webhook_logs` por `TO service_role` (ou por uma checagem de admin).
3. Desativar o `comprenozet-webhook-v2`. **Não** ligar o modo `strict` no v1: como a Zet não assina, ele recusaria todas as vendas. Em vez disso, trocar o endereço do webhook na Zet por um com token secreto e criar no Cloudflare uma regra de rate limit para `api.ruailuminada.com`.
4. Rotacionar as chaves do R2 e a `service_role`.
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
| `10-ASSISTENTE-FECHAMENTO.md` | Assistente de fechamento da bilheteria: problemas do atual e desenho por guichê, com tolerâncias |
| `13-ROBO-PAINEL-ZET.md` | Robô diário no painel da Zet para conciliar vendas, estornos, borderô e repasses com os webhooks |
| `14-MAPEAMENTO-PAINEL-ZET.md` | Telas e exports do painel da Zet; **R$ 975,00 em contestações sem webhook** (saldo negativo do evento na Zet); vendas na máquina da Zet |
| `15-IMPORTACAO-EXPORT-ZET.md` | Export de Transações: **fecha no centavo** com o painel (R$ 2.141.253,70); ponte webhooks → export; importação automática das vendas da máquina e dos webhooks perdidos |
| `12-RELATORIO-DIARIO-E-ACERTO-ZET.md` | Relatório diário (financeiro, público, ticket médio, previsão) e acerto final com a Zet; prazos de estorno |
| `11-VENDA-X-ENTRADA.md` | Por que o fechamento segue o dinheiro e não a catraca: três visões (caixa, acesso, competência) |
| `09-ANALISE-WEBHOOKS-ZET.md` | Análise dos 27.641 webhooks do backup: totais, 199 vendas nunca gravadas, segurança |
