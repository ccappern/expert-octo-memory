#!/usr/bin/env bash
# Kjører reparer.sql og deretter statussjekken mot Supabase.
#
# Tilkoblingsstrengen leses fra miljøvariabelen NORDLYS_DB, eller fra fila
# ~/.nordlys-db. Den skrives aldri ut, og skal ikke ligge i repoet.
#
# Hent den i Supabase: Project Settings -> Database -> Connection string.
# Bruk "Session pooler" (port 5432). Transaction pooler (6543) er ikke ment
# for DDL og kan oppføre seg uventet på et skript som dette.
#
#   echo 'postgresql://postgres.xxxx:PASSORD@aws-0-eu-north-1.pooler.supabase.com:5432/postgres' > ~/.nordlys-db
#   chmod 600 ~/.nordlys-db
#   ./supabase/kjor.sh
#
# psql kjøres i en docker-container, så ingenting må installeres lokalt.

set -euo pipefail
cd "$(dirname "$0")/.."

CONN="${NORDLYS_DB:-}"
if [ -z "$CONN" ] && [ -f "$HOME/.nordlys-db" ]; then
  CONN="$(tr -d '\r\n' < "$HOME/.nordlys-db")"
fi
if [ -z "$CONN" ]; then
  echo "Fant ingen tilkoblingsstreng." >&2
  echo "Sett NORDLYS_DB, eller legg strengen i ~/.nordlys-db (chmod 600)." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker kjører ikke. Start Docker Desktop og prøv igjen." >&2
  exit 1
fi

kjor() {  # fil, overskrift
  echo ""
  echo "=== $2 ==="
  # Strengen sendes som miljøvariabel og utvides INNE i containeren, slik at den
  # verken havner i vertens prosessliste eller i terminalloggen.
  docker run --rm -i -e PGCONN="$CONN" -v "$PWD:/w:ro" postgres:15 \
    sh -c 'psql "$PGCONN" -v ON_ERROR_STOP=1 -f "$1"' _ "/w/$1" 2>&1 \
    | grep -vE '^(SET|REVOKE|GRANT|ALTER TABLE|CREATE [A-Z]+|DROP [A-Z]+|DO|NOTIFY)$' || true
}

echo "Kobler til Supabase. Tilkoblingsstrengen skrives ikke ut."
kjor "supabase/reparer.sql"     "Reparerer skjemaet"
kjor "supabase/sjekk_status.sql" "Status etterpå"
echo ""
echo "Står alt på OK over, er databasen klar. Last siden på nytt."
