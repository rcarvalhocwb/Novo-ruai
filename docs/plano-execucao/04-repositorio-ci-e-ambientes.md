# 4. Repositório, ferramentas, CI e ambientes

## 4.1 Monorepo: **sim**, no próprio `Novo-ruai`

Motivo: `money.ts`, os schemas `zod` do payload da Zet e o contrato das catracas são usados por quatro peças diferentes (Workers, robô, painel e testes). Um monorepo garante que todas usem **a mesma versão** da regra de dinheiro. Tudo em TypeScript, exceto o SQL.

```
Novo-ruai/
├─ apps/
│  └─ web/                    # painel React + Vite (Cloudflare Pages). Só lê views e chama RPC api.*
├─ workers/
│  ├─ zet-ingest/             # borda do webhook: token, limite de corpo, R2, fila. Não conhece o banco
│  ├─ zet-consumer/           # fila → integ.receive_webhook via Hyperdrive
│  ├─ catracas-api/           # contrato v1 das catracas
│  └─ status/                 # página de status + health checks (cron trigger)
├─ services/
│  └─ robo-zet/               # Playwright (Fly.io): robô do painel, importador EDI PagBank, gerador de PDF
├─ packages/
│  ├─ money/                  # money.ts: Cents, toCentsStrict, parseBRL, applyRate, allocate, formatBRL
│  ├─ zet-schema/             # zod do webhook CP/ES e das planilhas exportadas; parser xlsx → linhas em centavos
│  └─ contracts/              # contrato v1 das catracas: tipos + exemplos/*.json (compartilhados com o conexao-topdata)
├─ supabase/
│  ├─ migrations/             # só DDL e funções; proibido DELETE/UPDATE/TRUNCATE de dados
│  ├─ tests/                  # pgTAP
│  └─ seed/                   # cadastro fictício para dev e hml (nenhum dado pessoal real)
├─ tools/
│  ├─ ci/                     # checagens próprias (políticas, colunas de dinheiro, migrações)
│  ├─ load/                   # k6: carga do webhook
│  └─ backup/                 # script do pg_dump → B2
└─ docs/
```

## 4.2 Ferramentas

| Área | Escolha | Motivo |
|---|---|---|
| Linguagem | TypeScript estrito (`strict`, `noUncheckedIndexedAccess`) | Uma linguagem para Workers, robô e painel |
| Pacotes | pnpm workspaces | Monorepo simples |
| Painel | React 18 + Vite + TanStack Query + React Router; `@supabase/supabase-js` | Equipe já conhece; só leitura por views |
| Validação | `zod` | Payload da Zet e contrato das catracas validados na borda e nos testes |
| Testes TS | Vitest + fast-check | Propriedades de `money.ts` |
| Testes SQL | pgTAP via `supabase test db` | Invariantes do livro-razão no banco |
| Workers | Wrangler; testes com Miniflare (`@cloudflare/vitest-pool-workers`) | Fila e R2 simulados no CI |
| Robô | Playwright (Chromium), imagem Docker, Fly.io | Browser completo com download de arquivos |
| PDF | HTML do relatório renderizado pelo mesmo Chromium do robô (`page.pdf`), a partir do JSON devolvido por `api.day_report()` com o hash do dia | O modelo aprovado em `modelo-relatorio/` vira o gabarito visual |
| Carga | k6 | 200 req/s reproduzível |
| Segredos no repositório | gitleaks (pre-commit e CI) | — |
| Lint | ESLint + Prettier; `sqlfluff` para as migrações | — |

Regra de revisão: **nenhum `number` para dinheiro**. ESLint customizado reprova `parseFloat`, `toFixed` e `Math.round` fora de `packages/money`.

## 4.3 CI (GitHub Actions)

Todo PR roda, e qualquer falha bloqueia o merge:

| Job | O que faz | Reprova quando |
|---|---|---|
| `lint` | ESLint, Prettier, `sqlfluff` | Estilo, `parseFloat`/`toFixed`/`Math.round` fora de `money` |
| `typecheck` | `tsc --noEmit` em todos os pacotes | Erro de tipo |
| `unit` | Vitest; fast-check com 10.000 casos por propriedade | `sum(allocate(t, w)) !== t`, arredondamento diferente do half-up, `parseBRL` sem ida e volta |
| `workers` | Vitest com Miniflare | Token errado ≠ 404; corpo > 64 KB ≠ 413; resposta 200 sem objeto no R2 |
| `pgtap` | `supabase start` + `supabase db reset` + `supabase test db` | Qualquer teste pgTAP falhar (lista em `07-plano-de-testes.md`) |
| `policies` | Script SQL em `tools/ci/` contra o banco do job | Existe policy com `qual = 'true'` ou `with_check = 'true'`; tabela sem RLS em qualquer schema; schema exposto além de `api`; função `security definer` sem `set search_path`; `GRANT` de `DELETE`/`TRUNCATE` em `fin`, `integ`, `recon`, `access`, `audit` para papel de aplicação |
| `money-columns` | Consulta ao `information_schema.columns` | Coluna com nome `*_cents` ou `amount*` que não seja `bigint`; qualquer coluna `real`, `double precision`, `money` ou `numeric` nos schemas financeiros |
| `migrations` | Varredura textual das migrações novas | `DELETE FROM`, `TRUNCATE`, `UPDATE ... SET` em tabela de dados, `DROP TABLE` de tabela financeira, `ON DELETE CASCADE` |
| `contracts` | Testes que leem `packages/contracts/exemplos/*.json` e validam requisição e resposta contra a `catracas-api` (Miniflare + banco do job) | Exemplo não passa; resposta sem `aceitos`/`repetidos`/`rejeitados` |
| `gitleaks` | Varredura de todo o histórico do PR | Qualquer segredo |
| `pii` | Varredura de `docs/` e `supabase/seed/` por padrões de CPF, e-mail e telefone | Dado pessoal no repositório |

Deploy:
- `main` → homologação automático (migrações, Workers `--env hml`, Pages preview, imagem do robô).
- Produção só por **tag** `vAAAA.MM.DD-N`, com aprovação manual no GitHub Environment `producao` (duas pessoas quando houver), migrações primeiro, depois Workers, depois painel.

## 4.4 Ambientes

| Ambiente | Banco | Borda | Dados | Quem usa |
|---|---|---|---|---|
| Desenvolvimento | `supabase start` local | `wrangler dev` | `supabase/seed` fictício | Cada desenvolvedor |
| Homologação (`hml`) | Projeto Supabase separado, Micro | Workers `--env hml` em `*-hml.ruailuminada.com`; fila e bucket próprios | Seed fictício + webhooks de um **evento de teste na Zet** (**A CONFIRMAR** com a Zet) + dados de 2025 **anonimizados** para o ensaio | Testes, ensaio conjunto com as catracas, ensaio geral |
| Produção | Projeto novo, Small, PITR | Workers `--env production` | Real | Operação |

Regras:
- **Nada de teste no endpoint de produção** (em 2025 um envio pelo Postman virou venda real). O token de produção só existe no cofre e no painel da Zet.
- Cada ambiente tem os seus segredos; nenhum segredo é compartilhado entre `hml` e produção.
- Dados de 2025 com dado pessoal **nunca** entram em `hml`; a anonimização roda fora do repositório e só o resultado anonimizado sobe.

## 4.5 Segredos (nomes das variáveis; os valores são cadastrados pelo dono em cada ambiente)

| Variável | Onde | Uso |
|---|---|---|
| `ZET_URL_TOKEN` | Segredo do Worker `zet-ingest` | Token do caminho do webhook |
| `HYPERDRIVE_*` (binding) | Configuração do Hyperdrive | Conexão dos Workers com usuário de papel mínimo |
| `ZET_PANEL_URL`, `ZET_PANEL_USER`, `ZET_PANEL_PASSWORD` | Segredos do Fly.io (`fly secrets set`) | Login do robô |
| `ROBO_FILE_KEY` | Segredo do Fly.io | Cifra dos arquivos baixados antes de ir ao R2 |
| `ROBO_API_EMAIL`, `ROBO_API_PASSWORD` | Segredo do Fly.io | Usuário do Auth com papel `importador` |
| `PAGBANK_EDI_USER`, `PAGBANK_EDI_TOKEN` | Segredo do Fly.io | API do Extrato EDI |
| `B2_KEY_ID`, `B2_APP_KEY` | Segredo do GitHub Environment `producao` | Upload do dump (chave sem permissão de apagar) |
| `BACKUP_DB_URL` | Segredo do GitHub Environment `producao` | `pg_dump` com `backup_reader` |
| `SUPABASE_ACCESS_TOKEN` | Segredo do GitHub Environment `producao` | Migrações |
| `ALERT_*` | Segredo do Worker `status` | Canal de alerta (e-mail ou Telegram; ver pergunta D-08) |

Rotação: `ZET_URL_TOKEN` a cada vazamento suspeito e ao fim da temporada (exige editar o link no painel da Zet); segredos de PC de catraca a cada temporada ou quando o PC trocar; demais a cada 90 dias. Procedimento no runbook.
