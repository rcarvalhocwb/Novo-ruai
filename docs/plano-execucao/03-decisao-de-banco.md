# 3. Decisão de banco

## Veredito: **confirmada**, com dois ajustes

**PostgreSQL gerenciado no Supabase, plano Pro, projeto novo, região São Paulo (`sa-east-1`).**

Motivos, em ordem de peso:
1. O DDL de `03`, `04`, `10`, `12`, `13`, `15` e `16` foi escrito e testado em Postgres. Trocar de banco agora custa as semanas que não existem.
2. Auth com MFA (TOTP), RLS, `pgmq`, `pg_cron`, PITR e pooler vêm prontos. Cada um desses seria uma peça a montar em outro provedor.
3. O dono do evento já opera Supabase.
4. `sa-east-1` deixa o banco perto dos guichês e fora da região que caiu em 2025 (us-east-1). A queda de região em si **não** é resolvida pela região: é resolvida pela borda durável (a fila guarda tudo enquanto o banco está fora) e pela fila local das catracas.

**Não reaproveitar o projeto antigo.** Ele tem RLS aberta, 111 funções, dados pessoais e histórico de migrações que apagam dados. O projeto antigo vira evidência congelada (`08-plano-de-virada.md`).

Os dois ajustes à recomendação original:
- **Sem réplica de leitura** em 2026 (motivo abaixo).
- **O backup externo não fica na Cloudflare nem na AWS**: vai para um terceiro provedor (Backblaze B2), com credencial que não apaga.

## Parâmetros

| Item | Decisão | Motivo |
|---|---|---|
| Plano | Pro | PITR e backups diários só existem em planos pagos |
| Região | `sa-east-1` (São Paulo) | Latência e distância da região de 2025 |
| Versão | A que o Supabase oferecer no projeto novo (15 ou superior). O DDL usa só recursos do Postgres 15+ (`btree_gist`, `constraint trigger`, `generated column`) | — |
| Compute produção | **Small** | Ver dimensionamento |
| Compute homologação | Micro (pausado fora da temporada) | Só testes e ensaio |
| PITR | **7 dias** de retenção, ligado de 01/10/2026 até o acerto final com a Zet | RPO ≤ 5 min. O Supabase exige compute Small ou maior para PITR |
| Pooler | Supavisor em modo transação para PostgREST e para clientes técnicos que não usam Hyperdrive; modo sessão só para `pg_dump`. Hyperdrive (Cloudflare) para os Workers | Nada abre conexão direta, exceto migração |
| Conexão direta | Só migrações, pelo CI com aprovação | Menor superfície |
| Schemas | `api` (único exposto), `fin`, `sales`, `integ`, `recon`, `access`, `audit`, `recovery` (fica vazio em 2026) | `03-ARQUITETURA-ALVO.md` |
| Extensões | `pgcrypto`, `btree_gist`, `pgmq`, `pg_cron`, `pgtap` (só hml e CI) | — |

## Dimensionamento pelo pico de 2025

Dados de `09-ANALISE-WEBHOOKS-ZET.md` e `dados/zet-webhooks-resumo-diario.csv`:

| Medida | 2025 | Carga no banco |
|---|---|---|
| Webhooks na temporada | 27.641 em 75 dias | ~370 por dia em média |
| Maior dia em pedidos | 943 pedidos (20/12/2025) | Menos de 1 por minuto em média; mesmo concentrados em 1 hora, ~0,3 por segundo |
| Maior dia em ingressos com visita | ~3.800 (20/12/2025: 3.832) | Público: tentativas de catraca da bilheteria somam na mesma ordem de grandeza |
| Linhas do livro-razão por pedido | 1 lançamento, 2 partidas; estorno por voucher, 2 partidas cada | < 100 mil partidas na temporada |
| Corpo cru por webhook | poucos KB | < 200 MB de inbox na temporada |

Conclusão: **o volume é pequeno**. O que derrubou 2025 não foi volume, foi amplificação (46 operações por requisição, sem transação, com `sleep`) e dependência síncrona do banco. O desenho novo faz 1 INSERT por webhook, fora do caminho de resposta. **Small** (2 GB de RAM) sobra; o limite real é o número de conexões, controlado pelo pooler e pela concorrência máxima de cada cliente técnico. Revisar no ensaio geral: se o p95 das RPC do fechamento passar de 300 ms, subir para Medium só durante a temporada.

## Réplica de leitura: **não**

- O banco não está perto do limite (acima).
- Relatório assinado precisa ler **exatamente** o que foi lançado. Réplica tem atraso, e um hash calculado na réplica pode divergir do primário no instante da assinatura.
- Relatórios pesados (conta-corrente Zet do evento inteiro, competência) viram views materializadas atualizadas por `pg_cron` fora do horário de fechamento, no próprio primário.

Revisar em 2027, se o painel ao vivo de público crescer.

## O que fica fora do Postgres

| Dado | Onde | Por quê |
|---|---|---|
| Corpo cru de cada webhook | **R2** (`zet/AAAA-MM-DD/<sha256>.json`) **e** `integ.webhook_inbox.raw_body` | O R2 é a cópia que existe mesmo com o banco fora; o inbox é a cópia consultável. Os dois são imutáveis |
| Arquivos baixados pelo robô (export de Transações, Lista de ingressos, Extrato, Detalhes) | **R2**, cifrados com chave própria (`ROBO_FILE_KEY`), com retenção definida (**proposta: até 5 anos após o acerto final, prazo a confirmar com o contador**) | Contêm CPF, e-mail e telefone. No banco entra só o que é normalizado e sem dado pessoal, mais o `sha256` do arquivo |
| Fotos da contagem e do relatório da maquininha | Supabase Storage, bucket privado, caminho com o `session_id` | Evidência do fechamento |
| PDFs dos fechamentos assinados | Supabase Storage, bucket privado, **e** cópia no B2 junto com o dump | Evidência |
| `pg_dump` diário | **Backblaze B2** com *object lock* (modo compliance, 90 dias), em conta separada; a chave do job só grava | Um ataque ou erro no Supabase ou na Cloudflare não apaga o backup |

## Backup e restauração

| Item | Como | Verificação |
|---|---|---|
| PITR | Add-on do Supabase, 7 dias | Restauração de teste num projeto separado, **todo mês** e antes do ensaio geral |
| Dump diário | GitHub Actions às 04:00 BRT: `pg_dump --format=custom` completo, pelo pooler em modo sessão, com o usuário `backup_reader`; `sha256` do arquivo registrado; upload para o B2 | Alerta se falhar; tamanho e contagem de linhas por tabela comparados com o dia anterior |
| Teste de restauração mensal | Restaura o último dump num projeto de homologação, roda `select count(*)` por tabela e confere os saldos do livro-razão contra o último dia fechado | Registrar data e responsável (checklist `07`, parte B) |
| RTO | 2 h | Medido no teste de restauração |
