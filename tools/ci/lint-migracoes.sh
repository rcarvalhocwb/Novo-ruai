#!/usr/bin/env bash
# Migração só mexe em schema. Reprova DELETE/UPDATE/TRUNCATE de dados, DROP TABLE e ON DELETE CASCADE.
# Comentários (-- ...) são ignorados.
set -euo pipefail
cd "$(dirname "$0")/../.."
falhou=0
for f in supabase/migrations/*.sql; do
  sem_comentario=$(sed -E 's/--.*$//' "$f")
  for padrao in 'delete[[:space:]]+from' '^[[:space:]]*truncate[[:space:]]+(table[[:space:]]+)?[a-z_]' 'drop[[:space:]]+table' 'on[[:space:]]+delete[[:space:]]+cascade' \
                '^[[:space:]]*update[[:space:]]+[a-z_]+\.[a-z_]+[[:space:]]+set'; do
    # "update ... set" dentro de corpo de função (indentado com 2+ espaços) é permitido
    achados=$(echo "$sem_comentario" | grep -niE "$padrao" | grep -vE '^[0-9]+:[[:space:]]{2,}' || true)
    if [ -n "$achados" ]; then
      echo "PROIBIDO em $f ($padrao):"; echo "$achados"; falhou=1
    fi
  done
done
[ "$falhou" -eq 0 ] && echo "migrações ok"
exit "$falhou"
