# Roadmap de reconstrução

Cada fase entrega algo utilizável e tem **critério de aceite objetivo**. Uma fase só avança com a anterior aceita.

## Escopo de 2026 (decidido em 26/09/2026)

Datas: **vendas online a partir de 15/10**; **vendas de bilheteria e máquinas a partir de novembro**.

**Fica fora de 2026:** a tela de venda no guichê e o modo "por guichê". A bilheteria vende como hoje, e a conferência de ingressos é **total dos 9 guichês × catraca** (R28).

**Entra em 2026:** webhook Zet, robô, botão de sincronização, conexão com a catraca, fechamentos diários, tesouraria, sangria, foods e relatórios.

| Entrega | Até | Conteúdo mínimo | Referência |
|---|---|---|---|
| 1. Fundação | **06/10** | Projeto novo; livro-razão em centavos (`fin`), com testes; `money.ts`; papéis e permissões; só o schema `api` exposto | `03`, fase 1 |
| 2. Webhook Zet | **13/10** (2 dias de folga antes de 15/10) | Worker + fila + R2 com token novo; inbox imutável; processamento de venda e estorno por voucher; conta "A receber Zet"; teste de carga e de banco fora do ar | `04` |
| 3. Robô da Zet | **24/10** | Login com segredos do ambiente; export de Transações, Lista de ingressos e Extrato; importação das vendas sem webhook e das vendas da máquina; contestações; validações (R27); snapshot com hash; execução diária e botão **Sincronizar com a Zet** | `13`, `14`, `15` |
| 4. Conexão com a catraca | **31/10** | API mínima: sobem as tentativas e passagens (e a saúde); descem os cartões bloqueados e a configuração. **Não** inclui a venda de balcão nem a baixa na Zet | `16`, seção 4 |
| 5. Fechamento e tesouraria | **07/11** | Sessões de caixa dos 9 guichês; fundo de troco; sangrias na hora; contagem; tolerâncias; conferência **total** bilheteria × catraca; tesouraria zerada; duas assinaturas; dia travado | `10`, R28 |
| 6. Foods e relatórios | **14/11** | Comissões com vigência; repasses; falta de repasse; relatório do dia em PDF (modelo aprovado pela equipe); conta-corrente Zet | `12`, `modelo-relatorio/` |
| Ensaio geral | **antes da 1ª venda de bilheteria** | Um dia simulado com dados de 2025 anonimizados: fechamento = extrato, R$ 0,00 de diferença | fases 3 e 6 |

As datas pressupõem começar já. A ordem segue o calendário: o online começa primeiro, a bilheteria depois. Se algo atrasar, a entrega 2 (webhook) **não** pode atrasar. Até o robô ficar pronto, o export da Zet é baixado à mão, todo dia.

O restante das fases abaixo continua valendo como plano completo, a partir de 2027.

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
- Worker de borda no Cloudflare com fila durável, consumidor, inbox, worker e máquina de estados com estorno por ingresso (`04-INTEGRACAO-ZET.md`).
- De-para de eventos e tipos de ingresso.
- Borda com WAF e rate limit.
- Job diário de conciliação Zet × sistema.
- Robô diário no painel da Zet (vendas, estornos, borderô, repasses), com snapshot e hash, e conciliação automática (`13-ROBO-PAINEL-ZET.md`). Baixa os exports de Transações, Lista de ingressos e Extrato; só leitura, com lista de botões permitidos (`14-MAPEAMENTO-PAINEL-ZET.md`).
- Importação diária do export de Transações: cria as vendas da **máquina da Zet** e as de webhook perdido, pelo mesmo caminho do webhook; pedido que some do export vira exceção (`15-IMPORTACAO-EXPORT-ZET.md`).
- API para o sistema das catracas (Conexão Topdata): ingressos e configuração descem, tentativas, vendas de balcão e saúde sobem, com segredo por PC e testes de contrato compartilhados (`16-INTEGRACAO-CATRACAS.md`).
- Lançamento automático de contestações (chargeback / PIX MED) e taxas de saque a partir do extrato da Zet.
- Importação diária do borderô da Zet (validações) e relatório diário de público, ticket médio e previsão; extrato conta-corrente Zet (`12-RELATORIO-DIARIO-E-ACERTO-ZET.md`).

**Aceite:** os testes de webhook passam (token, duplicata, CP repetido com valor diferente, ES parcial, ES antes de CP, CP depois de ES, 50 CPs concorrentes geram 1 venda, **banco desligado durante o teste sem perder nenhum webhook**); teste de carga de 200 req/s sem degradar o banco; um dia de homologação com o relatório Zet × sistema **R$ 0,00**; importação do export de 2025 reproduz a ponte da seção 2 de `15-IMPORTACAO-EXPORT-ZET.md` no centavo.

## Fase 3: Bilheteria e fechamento (2 semanas)
- Sessões de caixa (abertura, fechamento, contagem) gerando lançamentos.
- Importação automática das maquininhas pela API do Extrato EDI do PagBank (D+1, por número de série → guichê), com a taxa real; CSV só como plano B; importador OFX do banco.
- Conciliação da catraca por ingresso, por tipo e por valor (`10-ASSISTENTE-FECHAMENTO.md`, seção 8).
- Tela de configurações do evento (tolerâncias, caixa mínimo, assinantes, contas bancárias).
- Botão **Sincronizar com a Zet** no wizard (fila no servidor, uma execução por vez, intervalo mínimo) e bloco "Zet no dia" no relatório (`13-ROBO-PAINEL-ZET.md`, seção 5a).
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
