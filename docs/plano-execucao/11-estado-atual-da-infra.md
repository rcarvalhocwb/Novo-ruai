# 11. Estado atual da infraestrutura (levantamento de 26/09/2026)

Levantamento **somente leitura**, feito pelos conectores do Supabase e da Cloudflare. **Decisão do dono do evento: nada é alterado no banco antigo.** Ele fica só para pesquisa e para a migração de dados para o projeto novo.

## Supabase

| Projeto | Ref | Região | Situação | Papel em 2026 |
|---|---|---|---|---|
| Rua Iluminada | `tzqriohyfazftfulwcuj` | sa-east-1 | Ativo, Postgres 17, 546 MB | **Sistema de 2025: só pesquisa e fonte da migração.** Não alterar |
| iluminada | `irjlrsiudyfezdalgkeh` | sa-east-1 | Inativo | Desconhecido (pergunta D-13) |
| `ruai-2026-hml` | — | sa-east-1 | **Não criado**: o conector expirou (timeout de 60 s) nas duas tentativas | Homologação do sistema novo |
| (nome = e-mail do dono da organização) | `pophyumvrwjxuufltzey` | **ca-central-1** (Canadá) | Criado pelo dono em 26/09, vazio | **Não usar**: a região não pode ser mudada depois de criado. Decisão: recriar em `sa-east-1`; este, vazio, pode ser apagado |
| **Iluminada2026** | `rxkvrcttkxwqmppdnxok` | **sa-east-1** | Criado pelo dono em 26/09. **Migrações 1 a 4 aplicadas** (fundação). Checagens de CI ok; security advisor sem erro nem aviso (só o aviso informativo de RLS sem policy, que é intencional: as tabelas negam tudo e o acesso é só pelas RPC do schema `api`) | Projeto do sistema novo |

A organização é **Pro**. Uma conta de outra pessoa é dona dela (D-14).

### O que o projeto antigo mostra (confirma `02-RELATORIO-DE-PROBLEMAS.md`)

| Item | Valor | Relação |
|---|---|---|
| `webhook_logs` | 27.641 linhas; último em 04/01/2026 20:36 BRT | Mesmo total do backup analisado em `09`. O webhook não recebe nada desde o fim do evento |
| `zet_sales_master` | 27.712 linhas | Fonte F7 da migração |
| Tabelas no `public` | 115, todas com RLS ligada | — |
| Policies `USING (true)`/`WITH CHECK (true)` | 56, sendo **27 abertas para `anon`/`public`** | S-05, S-06, S-07: `bank_transactions` (SELECT, INSERT, UPDATE, **DELETE**), `zet_sales_master` (INSERT, UPDATE), `webhook_logs` (INSERT, UPDATE), `access_events` (INSERT), `authorizations` (SELECT), `middleware_commands` (UPDATE), entre outras |
| Edge functions | **149 ativas**, 85 com `verify_jwt = false` | `r2-backup`, `reset-comprenozet-online-sales`, `cleanup-test-events`, `get-webhook-secret`, `remove-phantom-order`, `comprenozet-webhook(-v2)` e `middleware-*`, todas ativas e sem JWT (S-01 a S-04, S-17) |
| Security advisor | 1 erro (`security_definer_view`) e 6 avisos (`search_path` mutável, funções `security definer` executáveis por `anon`, OTP longo, proteção de senha vazada desligada, versão do Postgres com patch pendente) | — |

**Risco que continua aberto (RS-21):** enquanto essas funções e policies existirem, qualquer pessoa com a chave pública do app antigo pode apagar backups no R2, apagar vendas e alterar o extrato. Isso atinge justamente os dados que serão migrados. Mitigação sem alterar o banco: **fazer já uma cópia completa** (`pg_dump` e download do bucket R2) e guardá-la fora do Supabase com `sha256`, antes de começar a migração. Quem faz o dump precisa da senha do banco. Ela é cadastrada como segredo do ambiente, nunca enviada por mensagem.

## Cloudflare

| Recurso | Situação | Observação |
|---|---|---|
| Worker `apizet` | Ativo desde 07/10/2025, última alteração 24/11/2025 | É o antigo `comprenozet-webhook-proxy`: repassa **qualquer** POST, sem token, de forma síncrona, para `comprenozet-webhook` do projeto antigo (S-21, S-23). CORS `*` |
| R2 `ruailuminada` | Existe desde 08/12/2025 | Backups do sistema antigo (têm dados pessoais). Um endpoint público (`r2-backup`) consegue apagá-los |
| KV, Hyperdrive, D1 | Nenhum | Tudo do sistema novo será criado do zero |

Na virada (`08`), o Worker `apizet` e a rota dele saem do ar. Até lá, o link do webhook no painel da Zet **não** deve apontar para ele no evento de 2026.

## Repositórios

| Repositório | Papel |
|---|---|
| `rcarvalhocwb/Novo-ruai` | Sistema novo (continuidade) |
| `iluminadarua/iluminadarua2025` | Sistema de 2025: **só pesquisa** |
| `rcarvalhocwb/conexao-topdata` | Middleware das catracas (outro time); só leitura daqui |

## Novas perguntas

| ID | Pergunta | Para |
|---|---|---|
| D-13 | O que é o projeto inativo `iluminada` (`irjlrsiudyfezdalgkeh`)? Tem dados a preservar? | Dono do evento |
| D-14 | Os projetos de 2026 ficam na organização atual, cuja dona é a conta de outra pessoa? Quem paga, e quem tem acesso de dono? | Dono do evento |
| D-15 | Quem faz o `pg_dump` completo e o download do R2 do sistema antigo, e quando? (Pré-requisito da migração; o banco antigo não é alterado) | Dono do evento |

## Pendências no painel do projeto Iluminada2026 (só o dono consegue)

1. **Settings → API → Exposed schemas:** deixar só `api` (tirar `public` e `graphql_public`).
2. **Authentication → MFA:** ligar TOTP. Sem MFA, admin e aprovador são recusados pelo banco.
3. **Authentication → Password security:** ligar a proteção contra senhas vazadas.
4. Apagar o projeto vazio de ca-central-1 (`pophyumvrwjxuufltzey`).
