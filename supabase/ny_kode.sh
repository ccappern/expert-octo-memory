#!/usr/bin/env bash
# Setter ny passkode for workshopen.
#
#   ./supabase/ny_kode.sh              foreslår koder på formatet XXXX-XXXX
#   ./supabase/ny_kode.sh ABCD-2345    setter den koden
#
# Koden lagres bare som bcrypt-hash. Den skrives aldri til disk her, og den
# finnes ingen steder i repoet etterpå – du må notere den selv.
#
# VIKTIG: workshop_by_code slår opp på upper(btrim(koden)), så hashen må lages
# av STORE bokstaver. Skriptet gjør det om automatisk; gjør du det manuelt i
# SQL Editor med små bokstaver, vil ingen komme inn.
#
# VIKTIG: å bytte kode logger ut alle som allerede er inne. De kommer inn igjen
# med ny kode, men join_workshop oppretter da en NY deltaker, og de gamle
# vurderingene blir liggende igjen som en usynlig ekstra stemme i snittet.
# Sett koden ferdig FØR du sender den ut.

set -euo pipefail
cd "$(dirname "$0")/.."

# Alfabet uten tegn som forveksles når koden leses opp: I, O, 0 og 1 er ute.
ALFABET="ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

lag_kode() {
  python3 - "$ALFABET" <<'PY'
import secrets, sys
a = sys.argv[1]
print("-".join("".join(secrets.choice(a) for _ in range(4)) for _ in range(2)))
PY
}

if [ $# -eq 0 ]; then
  echo "Forslag til kode – formatet XXXX-XXXX, uten I, O, 0 og 1:"
  echo ""
  for i in 1 2 3 4 5; do echo "    $(lag_kode)"; done
  echo ""
  echo "Sett en av dem:   ./supabase/ny_kode.sh ABCD-2345"
  echo "Eller din egen:   ./supabase/ny_kode.sh XXXX-XXXX"
  exit 0
fi

KODE="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | xargs)"
ANTALL=$(printf '%s' "$KODE" | tr -cd 'A-Z0-9' | wc -c | tr -d ' ')

if [ "$ANTALL" -lt 6 ]; then
  echo "«${KODE}» har bare ${ANTALL} tegn som teller. Under seks er den gjettbar" >&2
  echo "på timer. Velg en lengre, eller endre grensen i dette skriptet." >&2
  exit 1
fi

WS="${NORDLYS_WORKSHOP:-Nordlys forprosjekt – workshop}"
SQL="update public.workshops
        set code_hash = extensions.crypt('${KODE}', extensions.gen_salt('bf', 8))
      where name = '${WS//\'/\'\'}'
      returning name;"

echo "Setter ny kode på «${WS}» …"
supabase db query --linked "$SQL" | tail -5

echo ""
echo "Kontrollerer at den virker, og at den gamle ikke gjør det:"
supabase db query --linked "
  select case when private_ok then 'ny kode: virker' else 'NY KODE VIRKER IKKE' end as resultat
  from (select exists(
    select 1 from public.workshops
     where code_hash = extensions.crypt(upper('${KODE}'), code_hash)) as private_ok) t;" | tail -4

echo ""
echo "Koden er:  $KODE"
echo "Noter den nå – den finnes ikke lagret noe sted i klartekst."
