# Banco do sistema novo

Fundação (entrega 1): schemas, papéis, livro-razão de partidas dobradas, auditoria, assinaturas e fechamento do dia.

| Pasta | Conteúdo |
|---|---|
| `migrations/` | Só DDL e funções. O CI reprova `DELETE FROM`, `TRUNCATE`, `DROP TABLE`, `UPDATE ... SET` fora de função e `ON DELETE CASCADE` |
| `tests/` | pgTAP: balanceamento, imutabilidade, idempotência, trava do dia, assinaturas, MFA e separação de funções |
| `local/` | Imitação mínima do Supabase (`auth.uid()`, `auth.jwt()`, papéis) para rodar tudo num Postgres puro. **Nunca aplicar no Supabase** |

## Rodar localmente

```bash
PGHOST=... PGPORT=... PGUSER=postgres tools/db-test.sh   # banco limpo + migrações + checagens + pgTAP
tools/ci/lint-migracoes.sh
```

## Aplicar num projeto Supabase

1. Aplicar `migrations/` em ordem (Supabase CLI `supabase db push` ou pelo conector).
2. **Settings → API → Exposed schemas: só `api`.** Tirar `public` e `graphql_public`.
3. Auth: MFA (TOTP) ligado. Papéis `admin` e `aprovador` só funcionam com sessão `aal2`.
4. Rodar o security advisor e as checagens de `tools/ci/checagens.sql` contra o projeto.

## Regras que o banco garante

- Todo lançamento tem D = C (trigger diferido, checado no COMMIT) e só usa contas do próprio evento.
- `journal_entries`, `postings`, `period_reopenings`, `period_signatures` e `audit.log` não aceitam `UPDATE`, `DELETE` nem `TRUNCATE`, nem do dono das tabelas.
- A mesma `idempotency_key` gera um único lançamento.
- Um dia fechado não aceita lançamento. Um fechamento em andamento bloqueia lançamentos no mesmo dia até terminar.
- O dia só fecha com 2 assinantes designados (vigência no instante da assinatura) sobre o mesmo hash. Um lançamento novo invalida as assinaturas.
- Quem lançou no dia não assina o dia. Quem assinou não reabre. Reabrir exige admin com MFA e motivo.
