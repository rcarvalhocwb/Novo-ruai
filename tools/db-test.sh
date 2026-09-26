#!/usr/bin/env bash
# Cria um banco limpo, aplica o stub do Supabase + migrações e roda os testes pgTAP e as checagens de CI.
# Uso: PGHOST=... PGPORT=... PGUSER=postgres tools/db-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-ruai_test}"
export PGOPTIONS='--client-min-messages=warning'
psql -v ON_ERROR_STOP=1 -qc "drop database if exists $DB" -c "create database $DB" postgres
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f supabase/local/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do
  echo "migração: $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
psql -v ON_ERROR_STOP=1 -q -d "$DB" -c "create extension if not exists pgtap with schema extensions"
echo "checagens de CI:"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tools/ci/checagens.sql
pg_prove -d "$DB" --ext .sql -r supabase/tests
echo "concorrência:"
DB="$DB" tools/ci/concorrencia-zet.sh
