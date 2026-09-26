# Prompt: planejar a execução e a construção do novo sistema Rua Iluminada

> Como usar: abrir uma sessão nova com os repositórios `rcarvalhocwb/Novo-ruai` (branch `claude/financial-system-rebuild-j5x3em`), `rcarvalhocwb/conexao-topdata` (branch `claude/gallant-wright-pdloor`, só leitura) e `iluminadarua/iluminadarua2025` (sistema antigo, só leitura), e colar o texto abaixo.

---

## Papel

Você é um arquiteto de software sênior e líder técnico. Tem experiência em sistemas financeiros de eventos, conciliação, Postgres/Supabase, Cloudflare e segurança de aplicações. Seu trabalho agora é **planejar**, não escrever o sistema: transformar a análise já feita num plano de execução que um time pequeno, apoiado por IA, consiga cumprir nas datas abaixo. Responda sempre em português do Brasil.

## Objetivo final do sistema

Um sistema próprio, no domínio **ruailuminada.com**, que controla o **dinheiro** do evento Rua Iluminada e **fecha cada dia no centavo**, com prova:
- vendas online (Zet), vendas da bilheteria física (9 guichês, dinheiro e maquininhas PagBank) e vendas na máquina da Zet;
- estornos e contestações;
- comissões das lojas de alimentação (foods);
- tesouraria, sangrias, depósitos e despesas;
- conta-corrente com a Zet ("Zet, você me deve tanto");
- público e ticket médio;
- relatório diário assinado por duas pessoas designadas.

O sistema antigo falhou por quatro motivos, e o novo precisa ser imune a eles:
1. divergência de centavos (float, arredondamento em lugares diferentes);
2. perda de webhooks da Zet no dia da queda da AWS (o endpoint dependia do banco);
3. impossibilidade de conciliar (sem livro-razão, dados sobrescritos);
4. falhas de segurança (funções públicas que apagavam dados, RLS aberta).

## O que ler primeiro (é a fonte da verdade; não reinvente o que já foi decidido)

No repositório `Novo-ruai`, pasta `docs/analise-iluminadarua2025/`, **todos** os arquivos, nesta ordem:

| Arquivo | Para quê |
|---|---|
| `00-RESUMO-EXECUTIVO.md` | Visão geral, causas-raiz, incidente |
| `01-LOGICA-DE-NEGOCIO.md` | **Regras R1 a R28, confirmadas pelo dono do evento: são requisitos** |
| `02-RELATORIO-DE-PROBLEMAS.md` | O que não repetir (S-xx segurança, P-xx centavos e lógica, C-xx concorrência, A-xx arquitetura) |
| `03-ARQUITETURA-ALVO.md` | Livro-razão de partidas dobradas, `money.ts`, DDL testado, plano de contas |
| `04-INTEGRACAO-ZET.md` | Borda durável do webhook, máquina de estados por voucher |
| `05-MIGRACAO-E-RECUPERACAO.md` | Fontes F1 a F12 para reconstruir o histórico de 2025 |
| `06-ROADMAP.md` | **Escopo e calendário de 2026** (seção "Escopo de 2026") e fases completas |
| `07-CHECKLISTS.md` | Fechamento diário e segurança para produção |
| `08-DUVIDAS.md` | Perguntas respondidas e em aberto |
| `09` a `12` | Análise dos webhooks, assistente de fechamento, venda × entrada, relatório diário e acerto com a Zet |
| `13` a `15` | Robô do painel da Zet, mapeamento das telas, importação do export (fecha no centavo com o painel) |
| `16-INTEGRACAO-CATRACAS.md` | Integração com o middleware das catracas e contrato v1 |
| `modelo-relatorio/` | Modelo do relatório de fechamento (PDF) e o script que o gera |

No repositório `conexao-topdata`, leia:
- `README.md`;
- `docs/15-integracao-e-sincronizacao.md`, `16-multiplos-provedores-de-ingresso.md`, `18-contrato-do-webhook.md`, `19-bilheteria-local-e-divisao-das-catracas.md` e `22-sistema-supabase.md`;
- os ADRs 0002, 0003, 0007, 0022 e 0023;
- as migrações em `src/Access.Infrastructure.SQLite/Migrations/`.

No sistema antigo, consulte só para confirmar o comportamento de negócio. **Não copie a arquitetura.**

## Decisões já tomadas (não reabrir sem motivo forte e explícito)

1. **Dinheiro em centavos inteiros** (`bigint`) em todo lugar. Taxas em basis points, arredondamento half-up num único lugar, rateio por maior resto (`money.ts`). Nenhum `float`, nenhuma soma no navegador.
2. **Livro-razão de partidas dobradas, append-only**:
   - lançamento balanceado garantido por trigger;
   - sem UPDATE/DELETE, correção só por estorno;
   - idempotência por chave;
   - dia fechado travado;
   - reabertura só por admin, com motivo.
3. **Fechamento segue o dinheiro**. A catraca e a validação mostram **pessoas**, nunca viram valor de caixa.
4. **Zet**:
   - a taxa de 10% é da Zet, e a receita do evento é o líquido;
   - estorno devolve só o ingresso;
   - estorno parcial por voucher;
   - a Zet **não assina** o webhook, então a credencial é um token na URL;
   - contestações só aparecem no extrato da Zet (R25);
   - existem vendas na máquina da Zet sem webhook (R26).
5. **Validação de ingressos (R27)**: a Zet é a fonte, o nosso sistema acompanha, e **nada é alterado no painel da Zet**. O robô só lê.
6. **Bilheteria (R28)**: em 2026, **sem registro de venda por guichê**. Cada guichê fecha dinheiro e maquininha. A conferência de ingressos é o **total dos 9 guichês × usos consumidos na catraca por categoria × preço**. O cartão é revendido no dia, então **não se contam cartões distintos**. O modo "por guichê" fica configurável para 2027.
7. **Tolerâncias** configuráveis por evento:
   - até R$ 1,00: justificativa opcional;
   - de R$ 1,01 a R$ 50,00: justificativa obrigatória;
   - acima de R$ 50,00: destaque para os assinantes.
8. **Dados pessoais** (CPF, e-mail, telefone, nome) **nunca** entram no repositório. Mascarados em relatórios e logs (LGPD).
9. **Segredos** só em variáveis de ambiente ou cofre, nunca no código, no chat ou em planilha.
10. **IA** só orienta. Não calcula nem grava valores.

## Escopo e datas de 2026 (confirmados pelo dono do evento)

- **Vendas online a partir de 15/10/2026.** Vendas na bilheteria e nas máquinas a partir de **novembro**.
- **Entra em 2026:**
  - webhook Zet;
  - **robô do painel da Zet** e **botão "Sincronizar com a Zet"**;
  - **conexão com a catraca**;
  - fechamentos diários;
  - tesouraria e sangria;
  - foods;
  - relatórios.
- **Fica para 2027:**
  - tela de venda no guichê e modo "por guichê";
  - aviso de consumo da catraca para a Zet.

Calendário proposto em `06-ROADMAP.md`:

| Entrega | Até |
|---|---|
| Fundação | 06/10 |
| **Webhook Zet** (não pode atrasar) | 13/10 |
| Robô + sincronização | 24/10 |
| Conexão com a catraca | 31/10 |
| Fechamento e tesouraria | 07/11 |
| Foods e relatórios | 14/11 |
| Ensaio geral | Antes da 1ª venda de bilheteria |

Valide se as datas são realistas. Se não forem, diga o que corta e o que protege.

## Infraestrutura: o que decidir e justificar

### Domínio próprio
Hoje `ruailuminada.com` já passa pelo Cloudflare, e o sistema antigo usava `api.ruailuminada.com`. Proponha o mapa de subdomínios, por exemplo:

| Subdomínio | Uso |
|---|---|
| `app.` | Painel |
| `api.` | API do painel |
| `ingest.` | Webhook da Zet, com token no caminho |
| `catracas.` | API do middleware das catracas |
| `status.` | Página de status |

Inclua certificados, HSTS, DNSSEC e CAA. **Troque o token e o endereço do webhook da Zet**: os antigos vazaram no código e na documentação.

### Banco de dados (recomendação a validar)
**PostgreSQL gerenciado no Supabase, plano Pro, projeto novo (não reaproveitar o antigo), na região de São Paulo (`sa-east-1`).**

Por quê:
- o dono já domina o Supabase;
- o DDL do `03` e do `10` a `16` foi testado em Postgres 16;
- Auth, RLS, filas (pgmq), `pg_cron` e PITR vêm prontos.

A região de São Paulo reduz a latência para os guichês e tira o sistema da região que caiu em 2025 (us-east-1). A queda de região em si é coberta pela borda durável: a fila guarda tudo enquanto o banco está fora.

Obrigatórios:
- PITR (RPO ≤ 5 min);
- `pg_dump` diário completo para um bucket fora do Supabase, com *object lock*;
- restauração testada todo mês;
- pooler de conexões (Supavisor) para tudo que não for migração;
- tamanho de compute dimensionado pelo pico de 2025: maior dia com cerca de 3.800 ingressos online com visita, e o volume de webhooks do backup em `09`.

Avalie e decida:
- se vale uma **réplica de leitura** para relatórios e painéis;
- se algum dado deve ficar fora do Postgres (ex.: os snapshots do robô no R2).

### Balanceamento de carga e escala
Seja honesto sobre o que precisa de balanceamento e o que não precisa:

| Componente | Como escala |
|---|---|
| Webhook Zet | **Cloudflare Worker** (roda na rede global, escala sozinho) → **Cloudflare Queue** → consumidor com lote e concorrência limitada → banco. O pico de reenvios (o que derrubou 2025) fica na fila, não no banco. Rate limit e WAF na frente |
| Painel (front) | Estático no Cloudflare Pages (ou equivalente), com CDN |
| API do painel e das catracas | Supabase (PostgREST/edge functions) atrás do Cloudflare (proxy, WAF, rate limit por rota e por token) |
| Banco | **Escritas não se balanceiam**: um primário, protegido por fila, pooler e limites. Leituras pesadas podem ir para réplica |
| Robô da Zet | **Uma** execução por vez (trava no banco: `integ.robot_runs`), num contêiner com Playwright fora do banco (ex.: Fly.io, Cloud Run ou Railway). Proponha e compare custo |
| Middleware das catracas | Um PC no evento, com todas as catracas. Decide sem internet. Não precisa de balanceamento, precisa de fila local (já existe) |

Se propuser Cloudflare Load Balancing, health checks ou failover entre origens, diga para qual componente e por quê.

## Integrações (todas)

| # | Integração | Sentido | Situação | Referência |
|---|---|---|---|---|
| 1 | **Webhook Zet** (CP venda, ES estorno) | Zet → nós | Desenhado e testado em SQL | `04`, `09` |
| 2 | **Robô do painel Zet** (Transações, Lista de ingressos, Extrato, Detalhes do pedido) | nós lemos | Desenhado; login e senha de teste existem (pedir como segredos `ZET_PANEL_URL`, `ZET_PANEL_USER`, `ZET_PANEL_PASSWORD`) | `13`, `14`, `15` |
| 3 | **PagBank Extrato EDI** (D+1, por número de série → guichê) | nós lemos | Desenhado | `10`, seção 7 |
| 4 | **Extrato bancário** (OFX/CSV) | importação | Desenhado | `03`, `recon.*` |
| 5 | **Middleware das catracas** (Conexão Topdata) | dois sentidos | Contrato v1 proposto | `16` |
| 6 | Carga do histórico de 2025 (export Zet, backup de webhooks, extratos) | importação única | Plano pronto | `05`, `15` |

### Como deve ser a integração com o middleware das catracas
Leia `16-INTEGRACAO-CATRACAS.md` e os docs do `conexao-topdata`. Regras:

1. **A catraca decide no PC local**, sem internet. A nuvem **nunca** fica no caminho do giro.
2. **O PC puxa e envia; a nuvem nunca abre conexão para o PC.** A rede das catracas não alcança a internet; só o PC fala com a nuvem.
3. **Um só receptor do webhook da Zet: o sistema novo.** O relé do projeto das catracas não é usado. As catracas buscam os ingressos já traduzidos para o formato do `docs/18` deles.
4. **Contrato v1** (seção 4 do `16`):
   - **desce** configuração (categorias, preços, cartões bloqueados) e, se um dia a catraca aceitar QR da Zet, os ingressos;
   - **sobe** cada tentativa com `id` gerado no PC (idempotência pelo `id`), a categoria fotografada na passagem, resultado, motivo, `giro_confirmado`, horário em UTC;
   - **sobe** a saúde das catracas;
   - **não existem** comando remoto (abrir catraca pela nuvem) nem aviso de consumo para a Zet.
5. **Segurança do contrato**:
   - um segredo por PC, rotacionável;
   - nunca `service_role`;
   - resposta com aceitos, repetidos e rejeitados por item;
   - paginação por cursor de sequência do servidor, nunca por relógio (o sistema antigo tinha o limite de 1.000 linhas);
   - número do cartão sempre texto, como o PC normalizou.
6. **Testes de contrato compartilhados**: um arquivo de exemplos de requisição e resposta que os dois repositórios usam nos testes.
7. **Ensaio conjunto** num projeto de teste, nunca na produção.

Em 2026, o que o sistema novo precisa das catracas é:
- usos consumidos por categoria, para a conferência total bilheteria × catraca, o público e o ticket médio;
- a saúde das catracas.

## Segurança (requisitos mínimos, cada um com como verificar)

- **Superfície**: só o schema `api` exposto; RLS em todas as tabelas, negando por padrão; nenhuma policy `USING (true)`; toda função checa o papel do usuário.
- **Papéis**:
  - `operador_caixa`, `gestor`, `aprovador`, `admin`, `importador` (robô), `catraca` (middleware);
  - separação de funções: quem lança não aprova, quem aprova não reabre;
  - **MFA** obrigatório para admin e aprovador.
- **Webhook**: token longo na URL, comparado em tempo constante; limite de corpo; WAF; rate limit; lista de IPs da Zet se existir; responde sem depender do banco.
- **Dados**:
  - livro-razão, inbox e auditoria append-only, testado;
  - FKs `ON DELETE RESTRICT`;
  - nenhum `DELETE` em migração;
  - CPF e telefone mascarados.
- **Segredos**: cofre ou variáveis do projeto; `gitleaks` no CI; rotação documentada; o login do robô preferencialmente como usuário **só leitura** na Zet (pedir).
- **Robô**: lista de botões permitidos (navegação, filtros, Exportar, Detalhes, Fechar); aborta diante de formulário ou confirmação inesperada; nunca clica em Validar, Nova venda ou Solicitar saque.
- **Operação**:
  - CORS só do domínio do app;
  - logs com `correlation_id` e sem dado pessoal;
  - alertas (fila parada, robô falhou, catraca sem sinal, exceção de conciliação há mais de 24 h);
  - runbook de incidente;
  - página de status.
- **Checklist** `07-CHECKLISTS.md`, parte B, 100% verde antes de produção.

## O que você deve entregar

1. **Resumo de entendimento** (uma página): o que o sistema faz, para quem, e o que muda em relação a 2025.
2. **Arquitetura de produção**:
   - diagrama com domínio e subdomínios, Cloudflare, Supabase, fila, R2, contêiner do robô e PC das catracas;
   - para cada componente: onde roda, como escala, como falha e o que acontece quando falha;
   - custo mensal estimado.
3. **Decisão de banco** confirmada ou contestada, com região, plano, compute, PITR, pooler, réplica e backup externo.
4. **Estrutura do repositório** (monorepo ou não), ferramentas, CI (lint, typecheck, testes, pgTAP, testes de contrato, `gitleaks`, teste que falha com `USING (true)` ou coluna de dinheiro que não seja `bigint`) e ambientes (desenvolvimento, homologação, produção).
5. **Backlog por entrega** (as 6 do calendário + ensaio geral). Para cada item:
   - descrição;
   - critério de aceite testável;
   - dependências;
   - estimativa;
   - quem precisa fazer algo fora do código (Zet, PagBank, banco, dono do evento, time das catracas).
6. **Caminho crítico e plano B**, principalmente: o que fazer se o webhook não estiver pronto em 13/10 (o dado bruto não pode se perder), se a Zet não liberar usuário só leitura, se o PagBank não liberar o token EDI a tempo.
7. **Plano de testes**:
   - unidade;
   - pgTAP;
   - carga do webhook (200 req/s, banco desligado sem perder nada);
   - contrato com as catracas;
   - robô contra o export de 2025;
   - ensaio de um dia completo com diferença R$ 0,00.
8. **Plano de virada**: congelamento do sistema antigo, troca do link do webhook na Zet, carga do cadastro (eventos, lojas, tipos, preços, bancos, assinantes), e o que acontece com os dados de 2025.
9. **Riscos** com probabilidade, impacto e mitigação.
10. **Perguntas em aberto**, separadas por quem responde (dono do evento, Zet, PagBank, time das catracas), incluindo as que já estão em `08-DUVIDAS.md` e ainda não foram respondidas.

## Regras de trabalho

- **Não invente** API, campo, limite ou comportamento de terceiros (Zet, PagBank, Supabase, Cloudflare, Topdata). Se não souber, marque como `A CONFIRMAR` e diga quem confirma.
- Toda conta de dinheiro é em centavos. Todo exemplo numérico fecha.
- Não traga dados pessoais para o repositório nem para o plano.
- Não peça senha ou token no chat; peça para cadastrar como segredo do ambiente, com o nome da variável.
- Seja direto: recomende uma opção em cada decisão, com o motivo, em vez de listar alternativas sem escolher.
- Grave o plano em `docs/plano-execucao/` no repositório `Novo-ruai`, um arquivo por item acima. Abra ou atualize a PR, e faça um resumo curto no chat com o que precisa de decisão do dono do evento.
