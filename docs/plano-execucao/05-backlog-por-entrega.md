# 5. Backlog por entrega

Estimativas em **pessoa-dia (pd)** de um desenvolvedor experiente apoiado por IA, já incluindo os testes do item. O DDL de `03`, `04`, `10`, `12`, `13`, `15` e `16` é ponto de partida, não produto pronto: cada item o transforma em migração com pgTAP.

## 5.1 As datas são realistas? A conta

Dias úteis de 28/09 a 13/11/2026: 35, menos os feriados nacionais de 12/10 e 02/11 = **33 dias úteis**.

| Time | Capacidade | Backlog obrigatório (abaixo) | Folga |
|---|---|---|---|
| 1 desenvolvedor | 33 pd | 59,5 pd | **Não cabe.** Faltam 26,5 pd |
| **2 desenvolvedores** | 66 pd | 59,5 pd | 6,5 pd (~10%). Cabe, apertado |
| 3 desenvolvedores | 99 pd | 59,5 pd | Confortável, mas o ganho real é menor (coordenação) |

**Veredito:** o calendário é viável **com 2 desenvolvedores em tempo integral a partir de 28/09** e com as dependências externas (Zet, PagBank, time das catracas) respondendo em até uma semana. Com 1 desenvolvedor, o calendário não se sustenta: ver o que se corta em `06-caminho-critico-e-plano-b.md`, seção 6.1. Tamanho do time: pergunta D-02.

### Ajustes propostos ao calendário

| Entrega | `06-ROADMAP` | Proposta | Por quê |
|---|---|---|---|
| 1. Fundação | 06/10 | **06/10** | Mantida, só com o que o webhook precisa |
| 2a. **Borda durável em produção** | — | **09/10** (novo marco) | É o que protege o dado bruto. Com ela no ar, um atraso no processador não perde nada |
| 2b. Webhook completo | 13/10 | **13/10** | Mantida. Não pode atrasar |
| 3a. **Importação do export por upload** | — | **20/10** (novo marco) | O importador é o núcleo; o robô é a automação dele. Com o upload, o export baixado à mão já concilia |
| 3b. Robô + botão "Sincronizar" | 24/10 | **24/10** | Mantida; pode escorregar sem dano (plano B: upload diário) |
| 4. Conexão com a catraca | 31/10 | **31/10 (nosso lado)** | O lado do PC depende do ensaio de bancada deles (`HIL-STACK-01`), ainda não feito. Risco RS-05 |
| 5. Fechamento e tesouraria | 07/11 | **07/11** | Mantida, e inclui o PDF mínimo do dia (sem ele não há assinatura) |
| 6. Foods, conta-corrente Zet | 14/11 | **11/11** se a bilheteria abrir em 14/11 | O ensaio geral precisa de 2 dias **antes** da 1ª venda de bilheteria. Data de abertura: pergunta D-03 |
| Ensaio geral | antes da 1ª venda | **12 e 13/11** (se a abertura for 14/11) | — |
| 6b. Relatórios complementares | — | **21/11** | Público, ticket médio, previsão, competência e casamento automático do OFX não impedem fechar o dia no centavo |

Legenda de "fora do código": **Z** = Zet · **P** = PagBank · **B** = banco · **D** = dono do evento · **T** = time das catracas · **C** = contador.

## Entrega 1: Fundação (até 06/10) — 10,5 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| F-01 | Projetos Supabase (prod `sa-east-1` Small + PITR; hml Micro); só `api` exposto; Cloudflare: zona, DNSSEC, HSTS, CAA, TLS mínimo 1.2 | `curl` nos schemas `fin` e `public` via PostgREST devolve erro; `dig +dnssec` com `ad`; cabeçalho HSTS presente | — | 1 | **D**: cartão de crédito, acesso à conta Cloudflare e ao registrador do domínio |
| F-02 | Monorepo e CI completo (jobs de `04`, seção 4.3) | PR de teste com `USING (true)`, com coluna `numeric` de dinheiro, com `DELETE FROM` em migração e com um segredo falso: **os 4 são reprovados** | — | 2,5 | — |
| F-03 | `packages/money` | `applyRate(123456n,1500n)=18518n`; `applyRate(1005n,1000n)=101n`; `allocate(3000n,[2000n,1000n])=[2000n,1000n]`; `allocate(1000n,[1n,1n,1n])=[334n,333n,333n]`; propriedades com 10.000 casos | F-02 | 1 | — |
| F-04 | Schemas `fin` e `audit`: contas, períodos, lançamentos, partidas, `post_entry`, `reverse_entry`, trava de período, assinaturas com vigência, `close_period`, `day_snapshot`, auditoria genérica | pgTAP: lançamento desbalanceado rejeitado no COMMIT; `UPDATE`/`DELETE`/`TRUNCATE` em `journal_entries` e `postings` rejeitados (inclusive para o dono das tabelas por trigger); lançamento em dia fechado rejeitado; mesma `idempotency_key` 2× gera 1 lançamento; `close_period` com 1 assinatura falha; assinante fora da vigência falha | F-02 | 2,5 | — |
| F-05 | Papéis (`operador_caixa`, `gestor`, `aprovador`, `admin`, `importador`, `catraca`), RLS nega por padrão, RPC com `requireRole`, MFA obrigatório para `admin` e `aprovador`, separação de funções | pgTAP: `anon` não lê nem executa nada; `operador_caixa` não lê outro guichê; quem lançou no dia não assina o dia; quem assinou não reabre; RPC de admin sem fator MFA (`aal2`) falha | F-04 | 2 | **D**: lista de pessoas e papéis (sem dados pessoais no repositório; cadastro direto no Auth) |
| F-06 | Cadastros mínimos: evento 2026, plano de contas gerado por função, `zet_event_map`, `zet_ticket_type_map` por `eventsValues.id`, `event_settings` com tolerâncias R17 | Função cria o plano de contas de `03`, seção 3.2, idempotente; de-para rejeita texto de descrição como chave | F-04 | 1,5 | **Z**: `event.id` do evento 2026 e a lista de `eventsValues.id` com preços (ou um webhook de teste) |

## Entrega 2: Webhook Zet (borda até 09/10; completo até 13/10) — 9 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| W-01 | Worker `zet-ingest` + R2 + Queue em **produção**, WAF (só `POST /zet/v1/*`), rate limit, limite de 64 KB, IP real (`cf-connecting-ip`) gravado na mensagem | Token errado → 404 sem objeto no R2; corpo de 65 KB → 413; corpo válido → 200 em p95 < 100 ms **com o consumidor desligado**; objeto no R2 com `sha256` igual ao corpo | F-01 | 1,5 | — |
| W-02 | `zet-consumer` + Hyperdrive + `integ.webhook_inbox` imutável + `integ.receive_webhook` (1 INSERT idempotente + `pgmq.send`) | Mesmo corpo 2× → 1 linha; `UPDATE` de `raw_body` rejeitado; `DELETE` rejeitado; usuário `ingest_writer` não lê nenhuma tabela | W-01, F-04 | 1,5 | — |
| W-03 | Processador `integ.process_inbox`: schema do payload, centavos estritos, de-para, `allocate` por `list_price_cents`, validação da taxa (1 centavo por ingresso), máquina de estados CP/ES por voucher, lançamentos `zet:CP:<uuid>` e `zet:ES:<uuid>:<voucher>`, exceções (`amount_mismatch`, estorno órfão, CP após ES, evento/tipo sem de-para), dado cadastral nunca bloqueia | Exemplo: pedido com 1 inteira + 1 meia, bruto R$ 59,40, taxa R$ 5,40 → líquido R$ 54,00 rateado em R$ 36,00 + R$ 18,00; ES só da meia → estorno de R$ 18,00, pedido `PARCIALMENTE_ESTORNADO`, saldo de "A receber Zet" R$ 36,00. CP repetido com valor diferente não sobrescreve e abre exceção | W-02, F-06 | 3 | — |
| W-04 | Reconciliação R2 × inbox (diária), fila morta, alerta "fila parada > 5 min" e "mensagem mais antiga > 10 min" | Mensagem apagada da fila à força reaparece no inbox pela reconciliação | W-02 | 1 | **D**: canal de alerta (D-08) |
| W-05 | Testes de carga e de queda (ver `07`, seção 7.3) e reprocessamento do backup de 2025 | 200 req/s por 5 min com o banco desligado: 60.000 aceitas, 60.000 no R2, 60.000 no inbox depois de religar, zero perda. Backup de 2025 processado **fora do repositório**: 26.111 pedidos pagos do evento 538, R$ 2.067.707,50 líquidos, 226 estornados (R$ 17.975,50), líquido final **R$ 2.049.732,00** | W-03 | 1,5 | — |
| W-06 | Virada: evento de teste na Zet apontando para `ingest-hml`, depois o evento 2026 apontando para `ingest` com o token novo | Webhook real de teste aparece no inbox de hml; em produção, o primeiro CP real vira lançamento | W-03 | 0,5 | **Z**: evento de teste e cadastro do link; **D**: editar o link no painel da Zet |

## Entrega 3: Importação, robô e "Sincronizar com a Zet" (upload até 20/10; robô até 24/10) — 9,5 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| R-01 | Importador do export de Transações por **upload** (`packages/zet-schema`): cabeçalho, `Total − Taxa − Desconto = Líquido` em toda linha, soma = receita líquida do painel, staging sem CPF/e-mail/celular, `recon.v_zet_export_diff`, criação de vendas `zet_export` (online) e `zet_maquina` (4.1.04), exceções (sem data, ausente no export) | Com o export de 2025: 27.451 pedidos, soma **R$ 2.141.253,70**; a ponte de `15`, seção 2, é reproduzida linha a linha no centavo; arquivo com uma linha adulterada é rejeitado inteiro | W-03 | 3 | — |
| R-02 | Importador da Lista de ingressos: `used_at` e `used_source = 'zet_painel'` (R27); voucher validado só do nosso lado vira exceção | Com a lista de 2025: 76.870 validados e 5.822 pendentes (total 82.692) | R-01 | 1 | — |
| R-03 | Importador do Extrato: créditos, contestações (4.9.03, estado `CONTESTADO`), saques (casam com o banco), taxa de saque (5.1.03) | Com o extrato de 2025: 13 contestações somando **R$ 975,00**; saldo "A receber Zet" negativo exibido como dívida do evento | R-01 | 1,5 | — |
| R-04 | Robô Playwright no Fly.io: login pelos segredos, **lista de botões permitidos** (navegação, filtros, Exportar, Detalhes, Fechar), aborta diante de formulário ou confirmação inesperada, baixa os 3 exports, abre Detalhes só dos pedidos `items_pending`, arquivos cifrados no R2 com `sha256`, execução diária às 03:00 | Teste com página falsa que oferece "Validar", "Nova venda" e "Solicitar saque": o robô aborta sem clicar. Contagem lida ≠ total do painel → execução descartada e alerta | R-01..R-03 | 3 | **Z**: usuário só leitura (Z-01); **D**: cadastrar `ZET_PANEL_*` como segredos |
| R-05 | `integ.robot_runs` + botão "Sincronizar com a Zet" (gestor/aprovador), progresso por etapa, 1 execução por vez, intervalo mínimo de 10 min, bloco "Zet no dia" | Dois cliques simultâneos → 1 execução; clique 3 min depois → recusado com o tempo restante; Zet fora → fechamento continua com "sem dados da Zet desde HH:MM" | R-04 | 1 | — |

## Entrega 4: Conexão com a catraca (nosso lado até 31/10) — 5,5 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| C-01 | Schema `access`: `edge_devices` (hash do segredo, rotação com dois segredos válidos na troca), `ticket_use_attempts` append-only com sequência do servidor, `device_health` | `UPDATE`/`DELETE` em tentativas rejeitados; segredo guardado só como hash | F-05 | 1 | — |
| C-02 | Worker `catracas-api` v1: `GET /catracas/v1/configuracao` (categorias, preços vigentes, guichês, intervalo de reuso, cartões bloqueados, versão); `GET /catracas/v1/ingressos?cursor=` (lote ≤ 500, cursor = sequência do servidor, formato do `docs/18` deles, traduzido do voucher); `POST /catracas/v1/tentativas` (idempotente pelo `id` da borda); `POST /catracas/v1/saude`. Respostas com `aceitos`, `repetidos` e `rejeitados` por item; 401 segredo errado; 413 lote grande. **Sem** comando remoto, **sem** aviso de consumo à Zet | Lote de 500 com 1 item inválido → 499 aceitos, 1 rejeitado com motivo; reenvio do mesmo lote → 500 repetidos; paginação de 1.200 ingressos em 3 páginas sem perder nenhum; número do cartão preservado como texto (`"00123"` continua `"00123"`) | C-01 | 2,5 | — |
| C-03 | `packages/contracts/exemplos/*.json` (requisição e resposta de cada chamada) e testes; cópia entregue ao `conexao-topdata` | Os mesmos arquivos passam nos testes dos dois repositórios | C-02 | 0,5 | **T**: incorporar os exemplos nos testes deles |
| C-04 | Dia operacional da tentativa calculado **na nuvem** (dia aberto da bilheteria no instante `ocorrido_em`); tentativa que chega depois do dia fechado entra como delta no relatório seguinte | Tentativa atrasada não altera dia assinado | C-01, F-04 | 0,5 | — |
| C-05 | Ensaio conjunto em hml (borda puxa configuração, sobe tentativas e saúde; relatório mostra bilheteria × catraca) | Roteiro de `07`, seção 7.4, sem falha | C-02 | 1 | **T**: `FonteDeIngressos`/`ConectorRest` apontando para o contrato v1; PC de bancada disponível |

## Entrega 5: Fechamento e tesouraria (até 07/11) — 13 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| T-01 | Configurações do evento: tolerâncias R17, caixa mínimo, limites R13, assinantes com vigência, contas bancárias (sem apagar), **preços da bilheteria por categoria com vigência**, maquininhas (série → guichê, com vigência), `box_office_ticket_control = 'total'` | Alteração registrada no `audit.log`; conta bancária não pode ser apagada | F-05 | 1,5 | **D**: preços dos cartões (D-04), contas, números de série das maquininhas |
| T-02 | Sessões dos 9 guichês: retirada do banco para os fundos (Banco → Tesouraria), abertura com fundo por operador (Tesouraria → Caixa N) com confirmação do operador, sangria parcial com dupla confirmação na hora, fechamento com contagem por cédula e moeda, receita em dinheiro derivada (`01`, fórmula), total de cartão/PIX declarado, fotos com hash | Exemplo: fundo R$ 200,00, sangria R$ 1.000,00, contado R$ 1.450,00 → receita em dinheiro R$ 2.250,00; saldo do Caixa N volta a R$ 0,00; Tesouraria recebe R$ 2.450,00 no dia (1.000,00 + 1.450,00). Contado + sangrias < fundo → lançamento de quebra, nunca receita negativa | T-01 | 3 | — |
| T-03 | PagBank: importação D+1 pela API do Extrato EDI (ou CSV, plano B) no robô; MDR real (5.1.02); conferência declarado × EDI por terminal com as faixas R17; liquidação zera "A receber PagBank" | Exemplo: declarado R$ 1.800,00; EDI bruto R$ 1.800,00, MDR R$ 41,04 → "A receber PagBank" R$ 1.758,96 até a liquidação; diferença de R$ 12,00 exige justificativa | T-02, R-04 | 2 | **P**: token EDI (P-01); **D**: número do estabelecimento |
| T-04 | `fin.box_office_check` (total dos 9 guichês × usos consumidos por categoria × preço) | Exemplo ilustrativo: receita dos 9 guichês R$ 40.500,00; catraca: inteira 700 × R$ 36,00 = R$ 25.200,00, meia 600 × R$ 18,00 = R$ 10.800,00, social 180 × R$ 25,00 = R$ 4.500,00 → esperado R$ 40.500,00, diferença R$ 0,00, nível `ok`. Com 5% a menos de entradas → `alerta` | C-01, T-02 | 1 | — |
| T-05 | Wizard do fechamento do dia: pré-condições (9 guichês fechados, fila vazia, sincronização tentada), resumo por conta, diferenças acima de R$ 50,00 em destaque com comentário obrigatório dos assinantes, rascunho em tabela separada, `day_snapshot`, duas assinaturas sobre o mesmo hash, `close_period`, reabertura só por admin com motivo (≥ 10 caracteres) | Lançamento novo depois da 1ª assinatura invalida a assinatura; abrir o wizard num dia fechado não altera nada; dia fechado rejeita lançamento | T-02, T-04, F-05 | 3 | **D**: designar os dois assinantes |
| T-06 | Sangria pós-fechamento (Tesouraria → Banco ou → Despesa com comprovante), transferência entre contas, alerta de Tesouraria não zerada antes da abertura seguinte | Tesouraria com R$ 0,01 às 10:00 do dia seguinte → alerta | T-05 | 1 | — |
| T-07 | Relatório do dia em PDF (mínimo): bloco A financeiro, destaques, assinaturas, hash e QR de verificação; página pública de verificação só confirma "hash válido/inválido" | PDF recalculado bate com o hash assinado; PDF adulterado → "inválido" | T-05 | 1,5 | **D**: aprovação do layout (já existe o modelo) |

## Entrega 6: Foods e relatórios (até 11/11 ou 14/11) — 9 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| A-01 | Lojas, percentual com vigência (`exclude using gist`), vendas declaradas, comissão = `applyRate` uma vez por loja e dia | Vendas R$ 1.234,56 × 15% → **R$ 185,18** (nunca 185,184) | T-01 | 1,5 | **D**: lojas e percentuais |
| A-02 | Repasse FIFO, crédito de loja (2.1.01), falta de repasse com alerta no próximo caixa, baixa só por admin com motivo (5.2.02) | Loja deve R$ 500,00 e paga R$ 450,00 → R$ 50,00 continuam no saldo 1.2.1N, com alerta e dias em aberto | A-01 | 1,5 | — |
| A-03 | Conta-corrente Zet ("Zet, você me deve") | Exemplo: vendas R$ 100.000,00 − estornos R$ 1.200,00 − contestações R$ 300,00 − saques R$ 90.000,00 − taxas de saque R$ 8,00 (2 × R$ 4,00) = **R$ 8.492,00** = saldo da conta 1.2.01 | R-03 | 1 | — |
| A-04 | Extrato bancário OFX/CSV (`recon.statement_lines`, sem duplicar arquivo) e casamento manual assistido (repasses Zet, liquidações PagBank, depósitos de sangria) | Mesmo arquivo 2× → recusado pelo `sha256`; dia só conta como conciliado com toda linha casada ou em exceção com responsável | T-06 | 1,5 | **B**: acesso ao OFX; **D**: quem baixa |
| A-05 | Observabilidade: alertas (fila parada, robô falhou, catraca sem sinal > 10 min no horário do evento, exceção de conciliação > 24 h, backup falhou), página de status, logs com `correlation_id` sem dado pessoal | Cada alerta disparado ao menos uma vez em hml | W-04 | 1,5 | — |
| A-06 | Runbook de incidente (quem desliga o quê, rotação de segredos, restauração, Zet fora, banco fora, catraca sem internet) | Simulação de mesa feita com o dono do evento | A-05 | 1 | **D** |
| A-07 | Relatórios complementares: público (catraca + Lista de ingressos), ticket médio (R23), previsão de público, competência (**para 21/11**) | Ticket médio calculado sobre quem entrou, com e sem cortesia | R-02, C-02 | 1 | — |

## Ensaio geral (12 e 13/11, antes da 1ª venda de bilheteria) — 3 pd

| ID | Item | Critério de aceite testável | Dep. | Est. | Fora do código |
|---|---|---|---|---|---|
| G-01 | Um dia simulado em hml com dados de 2025 **anonimizados**: webhooks do dia, export, extrato, 9 guichês, EDI, tentativas de catraca, foods, fechamento, assinaturas, sangria | **Diferença R$ 0,00** entre fechamento e extratos simulados; Tesouraria zerada; PDF assinado e verificado | Tudo | 1,5 | **D**: 2 assinantes e 2 operadores reais participam |
| G-02 | Restauração do backup testada, checklist `07`, parte B, 100% verde, teste com a chave `anon` contra todas as rotas (tudo 401/403) | Checklist assinado | Tudo | 1,5 | — |

**Total obrigatório: 10,5 + 9 + 9,5 + 5,5 + 13 + 9 + 3 = 59,5 pd.**

## 5.2 Divisão sugerida para 2 desenvolvedores

| Semana | Dev A (dinheiro e regras) | Dev B (borda, integrações, operação) |
|---|---|---|
| 28/09–02/10 | F-03, F-04 | F-01, F-02 |
| 05/10–09/10 | F-06, W-03 | F-05, W-01, W-02 (**borda em produção 09/10**) |
| 13/10–16/10 | W-03 (fim), W-05, W-06 | W-04, R-04 (início) |
| 19/10–23/10 | R-01, R-02, R-03 | R-04, R-05 |
| 26/10–30/10 | T-01, T-02 | C-01, C-02, C-03, C-04 |
| 03/11–06/11 | T-04, T-05 | T-03, C-05, T-06 |
| 09/11–11/11 | A-01, A-02, A-03 | T-07, A-04, A-05, A-06 |
| 12/11–13/11 | G-01 | G-02 |
| 16/11–21/11 | A-07 | Folga para correções pós-abertura |
