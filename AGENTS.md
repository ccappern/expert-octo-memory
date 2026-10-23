# AGENTS.md

Arbeidsinstruks for agenter i dette repoet.

`README.md` forklarer **hva** verktøyet er og hvorfor matrisen ser ut som den gjør. Denne
fila forklarer **hvordan du jobber i koden** uten å ødelegge noe. Les begge.

## Hva dette er

Workshopverktøy for Nordlys-forprosjektet. Deltakerne legger inn hypoteser, vurderer dem på
kritikalitet og usikkerhet (1–10), og ser resultatet live i en 2×2-matrise.

Statisk side på GitHub Pages mot en Supabase-database i Stockholm (eu-north-1).

## Harde begrensninger

Bevisste valg. Ikke bryt dem uten å spørre:

1. **Appen for deltakerne er én fil: `index.html`.** Ingen byggesteg, ingen pakkebehandler,
   ingen bundler, ingen CDN. `config.js` inneholder bare URL og publishable key.
   `admin.html` er det eneste bevisste unntaket: backend har et annet publikum, et annet
   livsløp, og skal ikke lastes ned av seksten deltakere som bare skal stemme. Den følger
   ellers nøyaktig samme konvensjoner, og gjenbruker innloggingen uendret.
2. **Ingen rammeverk.** Vanilla JS og vanlig CSS. Ingen React/Vue/Tailwind. DOM bygges med
   hjelperen `h()` og `s_()` for SVG.
3. **All tekst på norsk (bokmål).** Brukerrettet tekst *og* kodekommentarer.
4. **Kommentarer forklarer hvorfor, ikke hva.** Se de eksisterende: de begrunner valg og
   beskriver fellen som ble unngått. Kommentarer som gjentar koden skal ikke inn.
5. **Nøkler og koder hører ikke hjemme i repoet.** Workshopkoden deles muntlig.
   Tilkoblingsstrenger ligger i nøkkelringen eller `~/.nordlys-db`, aldri i en fil som
   committes.

## Database: bruk alltid Supabase CLI

**Dette er hovedregelen i dette repoet.** Ikke lim SQL inn i Supabase SQL Editor, og ikke
kjør psql direkte mot produksjon, selv om `kjor.sh` finnes og README beskriver den veien.
CLI-en er autentisert mot det lenkede prosjektet (`supabase/.temp/project-ref`) og henter
databasepassordet fra nøkkelringen.

```sh
supabase db query --linked "select ..."     # lesing og inspeksjon
supabase migration list --linked            # hva er faktisk anvendt
supabase db push                            # kjør nye migrasjoner
supabase migration repair --status applied <versjon>   # kun bokføring, kjører ingen SQL
```

### Fast rekkefølge ved skjemaendring

1. **Skriv migrasjonen** i `supabase/migrations/`, nummerert videre fra forrige.
2. **Valider lokalt mot en engangsbase først.** Aldri produksjon som første forsøk:
   ```sh
   docker run -d --name nordlystest -e POSTGRES_PASSWORD=p postgres:15
   docker exec nordlystest psql -U postgres -c "create schema extensions; create role anon; create role authenticated;"
   for f in supabase/migrations/0*.sql; do docker exec -i nordlystest psql -U postgres -v ON_ERROR_STOP=1 < "$f"; done
   ```
   `0003` og `0008` er seed-skript som feiler i en tom base fordi workshopen ikke finnes.
   Det er forventet, ikke en feil i migrasjonen.
3. **Funksjonstest regelen du innførte** i den lokale basen — ikke bare at SQL-en parser.
4. **Les faktisk fjerntilstand før push**: `supabase migration list --linked` og
   `supabase db query --linked` mot `information_schema` og `pg_proc`.
5. **Push.** Deretter verifiser med `supabase/sjekk_status.sql`.
6. **Først da publiseres `index.html`.** Se rekkefølgen under.

### Migrasjonshistorikken er ute av synk — sjekk før du pusher

Fjernbasen ble initialisert med én samlet migrasjon (`20261020082548 init_hypoteseregister`),
mens repoet har `0001`–`000N`. `supabase migration list --linked` viser derfor tom `remote`
for alle lokale filer.

**`supabase db push` vil da forsøke å kjøre `0001_init.sql` på nytt mot en base som allerede
har tabellene.** Kjør aldri push uten å ha sett lista først.

Riktig framgangsmåte når fjernskjemaet allerede tilsvarer de gamle migrasjonene: marker dem
som anvendt, slik at push bare tar den nye.

```sh
supabase migration list --linked
supabase migration repair --status applied 0001 0002 0003 0004 0005 0006 0007 0008
supabase db push          # kjører nå bare 0009 og nyere
```

Push stopper i tillegg på fjernmigrasjoner som ikke finnes lokalt
(`DbPushMissingLocalError`). Den opprinnelige `20261020082548 init_hypoteseregister` var
redundant etter at 0001–0008 ble markert anvendt, og ble fjernet fra historikken:

```sh
supabase migration repair --status reverted 20261020082548
```

`reverted` sletter bare raden i historikktabellen. Den kjører ingen nedmigrasjon og rører
ikke skjemaet.

`migration repair` skriver bare rader i `supabase_migrations.schema_migrations`. Den kjører
ingen SQL og kan ikke ødelegge data. Men bekreft at skjemaet faktisk *er* i den tilstanden
før du markerer noe som anvendt — ellers skjuler du et hull.

### To fallgruver som gir samme feilmelding

«Could not find the function … in the schema cache» har to helt ulike årsaker:

| Årsak | Symptom | Tiltak |
|---|---|---|
| Migrasjonen er ikke kjørt | `sjekk_status.sql` sier MANGLER | Kjør migrasjonen |
| PostgREST har gammel cache | `sjekk_status.sql` sier OK | `notify pgrst, 'reload schema';` |

**Enhver migrasjon som endrer en funksjonssignatur må avslutte med
`notify pgrst, 'reload schema';`** Uten den svarer API-et på den gamle signaturen selv om
databasen er riktig.

### Signaturendringer krever opprydding

Flere migrasjoner endrer signaturen på de samme funksjonene. Hver `drop function if exists`
treffer bare den utgaven den forventer. Hoppes én over, blir gamle utgaver liggende som
overlast og PostgREST velger feil.

Derfor: **endrer du en RPC-signatur, må `supabase/reparer.sql` oppdateres i samme slengen.**
Den er sannheten om endelig tilstand — den dropper alle utgaver og bygger dem opp på nytt.
Og legg til en rad i `supabase/sjekk_status.sql` for den nye migrasjonen.

Filer som skal følges ad når skjemaet endres:

- `supabase/migrations/NNNN_*.sql` – selve endringen
- `supabase/reparer.sql` – endelig tilstand, idempotent
- `supabase/sjekk_status.sql` – en rad som verifiserer den nye migrasjonen
- `README.md` – lista under «Filer»

## Utrullingsrekkefølge: SQL først, så klient

Klienten og RPC-ene henger sammen i signatur. Publiseres `index.html` før migrasjonen er
kjørt, sender den parametre databasen ikke kjenner, og handlingen feiler for alle deltakere.

**Alltid: migrer → verifiser → publiser.** Aldri motsatt.

Dette gjelder særlig under en pågående workshop. Sjekk antall vurderinger før du rører noe:

```sh
supabase db query --linked "select count(*) from public.ratings;"
```

## Testing

Det finnes ingen testsuite. Bruk nettleseren, og stub backenden.

- Server lokalt: `python3 -m http.server 8777`
- Kjører browseren i Docker, nås verten på `http://host.docker.internal:8777`
- Stub `window.fetch` i en `addInitScript` og legg en falsk økt i `localStorage` under
  nøkkelen `nordlys-hyp-session`. Da rendres hele appen uten ekte backend, og du kan
  verifisere både DOM-tilstand og hvilke RPC-kall som faktisk sendes.
- Sjekk alltid konsollen for feil til slutt.

Syntakssjekk av den innebygde JS-en uten nettleser:

```sh
node -e 'const s=require("fs").readFileSync("index.html","utf8");
[...s.matchAll(/<script>([\s\S]*?)<\/script>/g)].forEach(b=>new Function(b[1]));
console.log("OK")'
```

## Kodekonvensjoner i `index.html`

- Fila er seksjonert med `/* ---------- navn ---------- */`. Legg nytt der det hører hjemme.
- Alt ligger i én IIFE. Ingenting eksponeres globalt — det er med vilje, og betyr at tester
  må gå via DOM og nettverkslaget.
- `h(tag, attrs, ...kids)` bygger HTML, `s_(tag, attrs, text)` bygger SVG. `null` og `false`
  blant barn hoppes over, så `betingelse ? h(...) : null` er mønsteret.
- `$(id)` er `getElementById`.
- Matrisen tegnes på nytt ved hver poll (hvert fjerde sekund). **Alt som holder tilstand
  mot et DOM-element må tåle at elementet byttes ut.** Se gjenfestingen av hover-kortet i
  `renderMatrix()` for mønsteret.
- Lyttere som skal overleve opptegning settes på `#chart`, ikke på punktene. Se `mxDrag()`.
- Lister bygges på nytt ved hver poll. Fokus gjenopprettes via `data-fk`-attributtet — bryt
  ikke det, ellers mister deltakerne fokus midt i en vurdering.

## Domeneregler som er lette å bryte

- **Skalaen er 1–10 uten midtpunkt.** Grensen går ved 5,5 slik at ingen kan sitte på gjerdet.
  Endres `SKALA`, må `MIDT` og `SPRIK` vurderes på nytt.
- **Kritikalitet og usikkerhet er ikke symmetriske.** «Bekreftet» og «Avkreftet» nullstiller
  usikkerheten, men rører *ikke* kritikaliteten: en bekreftet kritisk antakelse er fortsatt
  kritisk, og det er nettopp derfor den er et premiss.
- **Avklart status krever belegg.** Håndheves både i klienten og i RPC-en, fordi regelen skal
  gjelde uansett klient.
- **Gruppens snitt skjules mens folk stemmer, og sperren ligger i databasen.** Ser du hvor
  flertallet ligger mens du stemmer, havner du der selv. `workshops.resultatvisning` har tre
  moduser: `lukket` (bare antall), `etter_stemme` (tallene åpnes per hypotese når du selv har
  vurdert den) og `apent`. `get_board` filtrerer radene før de sendes — filtrerer du bare i
  klienten, kan hvem som helst lese tallene med den publiserbare nøkkelen i `config.js`.
  Antallet vurderinger sendes alltid, i en egen `tellinger`-liste: det anker ingen retning.
- **Hvem som la inn en hypotese sendes ikke ut.** Registeret vedlikeholdes fra backend, og
  forfatteren er verken relevant eller noe deltakerne skal forholde seg til.
- **Eierlista ligger i `EIERE` i `index.html`, ikke som CHECK i databasen.** Teamnavn endrer
  seg midt i et prosjekt, og en omdøping skal ikke kreve migrasjon.
- **Leveransene ligger derimot i databasen (`public.deliverables`), ikke i klienten.** Det er
  motsatt av `EIERE`, og med vilje: kilden på Confluence har ødelagt nummerering og uavklart
  overlapp mellom to leveranser, så lista rettes flere ganger. Slug er nøkkelen, `nr` er bare
  presentasjon. Derfor koster en omnummerering null migrasjoner.
- **`admin.html` er ikke tilgangskontroll.** Fila ligger offentlig lesbar på GitHub Pages.
  Det er `private.meg_admin()` som stenger døra. Legger du til en ny admin-funksjon, må den
  starte med `meg_admin()` — ikke stol på at knappen er skjult.
- **Hypoteser slettes aldri, de arkiveres** (`deleted_at`). En ekte `delete` tar med seg alle
  vurderingene via cascade, og det finnes ingen angreknapp midt i en workshop.

## Publisering

GitHub Pages fra `main` / `(root)`. `.nojekyll` ligger der for at filer med understrek skal
serveres. Del adressen og workshopkoden muntlig — koden skal ikke i repoet.

## Confluence-synk

Registeret skrives automatisk til Confluence-siden
[Hypoteser](https://krafthack.atlassian.net/wiki/spaces/NF/pages/25526273/Hypoteser) av
edge-funksjonen `supabase/functions/confluence-sync`. Samme mønster som `confluence-sync` i
nettside-prosjektet.

Utløses av to ting:

- **Trigger** på `hypotheses` og `ratings`, på setningsnivå, sperret til ett kall i minuttet.
  Sperren er der fordi seksten personer som vurderer samtidig ellers ville hamret på
  Confluence-API-et.
- **pg_cron** hvert femte minutt (`confluence-sync-5min`), som fanger opp det triggeren
  måtte bomme på.

Funksjonen skriver bare når innholdet faktisk er endret. `confluence_sync_changed()` leser
og skriver summen i **én** setning, slik at to samtidige kjøringer ikke begge kan få `true`.
Tidsstempelet holdes utenfor summen, ellers ville hver kjøring sett ut som en endring.

Hemmeligheter settes med CLI, aldri i repoet:

```sh
supabase secrets set CONFLUENCE_BASE_URL="https://krafthack.atlassian.net" \
                     CONFLUENCE_PAGE_ID="25526273" \
                     CONFLUENCE_EMAIL="..." CONFLUENCE_API_TOKEN="..."
supabase functions deploy confluence-sync --no-verify-jwt
```

Mangler noen av dem, rapporterer funksjonen `hoppet_over` i stedet for å feile.

**Test uten å røre Confluence** med `?dry=1` — den returnerer den ferdige siden som HTML:

```sh
HEM=$(supabase db query --linked "select hemmelighet from private.confluence where id;" | grep -o '[a-f0-9]\{64\}')
curl -s -X POST "https://ryzeahdqxtclliyhdlki.supabase.co/functions/v1/confluence-sync?dry=1" \
     -H "x-sync-secret: $HEM" | head -c 2000
```

**Personvern:** individuelle vurderinger publiseres ikke. Siden viser snitt, antall
vurderinger og uenighetsflagget — aldri hvem som stemte hva. Det speiler at appen heller
ikke eksporterer enkeltstemmer. **Ikke legg enkeltstemmer på siden** uten å avklare det
med deltakerne først.
