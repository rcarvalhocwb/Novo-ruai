# Roadmap de reconstrução

Cada fase entrega algo utilizável e tem **critério de aceite objetivo**. Uma fase só avança com a anterior aceita.

## Fase 0: Contenção e evidências (1 a 3 dias)
- Ações urgentes no sistema antigo (`00-RESUMO-EXECUTIVO.md`).
- Dump completo, cópia do R2, export dos logs e pedido de backups ao suporte do Supabase.
- Pedir à Zet o relatório completo, o extrato de repasses e as respostas técnicas (`08-DUVIDAS.md`).

**Aceite:** nenhuma função pública consegue apagar ou alterar dado (teste com a chave anônima: todas devolvem 401/403); dump e arquivos R2 guardados com sha256 registrado.

## Fase 1: Fundação (1 a 2 semanas)
- Novo projeto Supabase (Pro + PITR). Só o schema `api` exposto na API.
- `money.ts` + testes de propriedade.
- Schemas `fin`, `audit` e `recon` (DDL de `03-ARQUITETURA-ALVO.md`) + testes pgTAP.
- Plano de contas do evento.
- Autenticação com papéis (`operador_caixa`, `gestor`, `aprovador`, `admin`) e MFA para admin.
- CI: lint, typecheck, testes, e um teste que falha se aparecer `USING (true)` sem `TO service_role` ou coluna monetária que não seja `bigint`.

**Aceite:** a suíte prova que lançamento desbalanceado, UPDATE/DELETE no livro-razão e lançamento em dia fechado são rejeitados; `allocate` e `applyRate` passam em mais de 10 mil casos aleatórios.

## Fase 2: Integração Zet (1 a 2 semanas)
- Endpoint fino, inbox, pgmq, worker e máquina de estados (`04-INTEGRACAO-ZET.md`).
- De-para de eventos e tipos de ingresso.
- Borda com WAF e rate limit.
- Job diário de conciliação Zet × sistema.

**Aceite:** os testes de webhook passam (assinatura, replay, duplicata, ES antes de CP, CP depois de ES, 50 CPs concorrentes geram 1 venda); teste de carga de 200 req/s sem degradar o banco; um dia de homologação com o relatório Zet × sistema **R$ 0,00**.

## Fase 3: Bilheteria e fechamento (2 semanas)
- Sessões de caixa (abertura, fechamento, contagem) gerando lançamentos.
- Importador PagBank (CSV) com MDR real; importador OFX do banco.
- Wizard de fechamento: esperado (livro-razão) × declarado; quebra e sobra como lançamento; assinatura; aprovação; trava do dia; hash no PDF.
- Rascunho em tabela separada.

**Aceite:** simulação de um dia completo com dados reais anonimizados do evento passado: fechamento = extrato; reabrir exige admin e motivo e fica registrado; é impossível alterar dia fechado.

## Fase 4: Foods (1 semana)
- Vendas declaradas, comissão com regra única, repasse FIFO em centavos, crédito de loja para excedente.
- Movimentos e fechamento da loja.

**Aceite:** para cada loja, Σ comissões − Σ repasses = saldo da conta "A receber loja N" = extrato da loja, sem diferença de centavo.

## Fase 5: Recuperação do histórico (em paralelo às fases 2 a 4)
- Schema `recovery`, carga das fontes F1 a F11, casamento, exceções, decisões e relatório por dia com os selos ✅🟡🔴 (`05-MIGRACAO-E-RECUPERACAO.md`).

**Aceite:** relatório de reconstrução assinado; saldo bancário reconstruído = extrato na data de corte.

## Fase 6: Relatórios, caixa geral e produção (1 a 2 semanas)
- Relatórios só por views e RPC (sem somas no navegador).
- Caixa geral e repasse à administração com caixa mínimo.
- Observabilidade e alertas; runbook; teste de restauração.
- Migrar cadastros (eventos, lojas, tipos, staff) e o módulo de catracas/RFID (fora do núcleo financeiro).

**Aceite:** checklist de segurança (`07-CHECKLISTS.md`) 100% verde; restauração testada; um dia de operação paralela (sistema antigo só leitura × novo) com diferença R$ 0,00.

## O que NÃO reconstruir
- As cerca de 30 funções de correção, reprocessamento e limpeza.
- Tabelas duplicadas de venda online.
- Somatórios no front-end.
- "Assistentes de IA" que gravam dados financeiros. Se forem mantidos, que sejam **somente leitura**.
