# Nordlys hypoteseregister

Workshopverktøy for Nordlys-forprosjektet. Deltakerne legger inn hypoteser på formen
«Vi tror at … / Vi vet det når …», vurderer hver hypotese på kritikalitet og usikkerhet (1–5),
og ser resultatet live i en 2×2-matrise.

Statisk side (GitHub Pages) mot en Supabase-database i Stockholm (eu-north-1).

## De fire feltene

Matrisen er ikke en oversikt, den er et filter som sorterer hypotesene i det anbefalingen
til styringsgruppen skal bygges av:

| Felt | Betyr | Seksjon i anbefalingen |
|---|---|---|
| Kritisk + usikker | Vi kan ikke anbefale noe før dette er avklart | **Må avklares** – med eier og frist |
| Kritisk + avklart | Anbefalingen hviler på dette | **Dette bygger vi på** – premisser som kan bestrides |
| Lite kritisk + usikker | Vi vet det ikke, og velger å leve med det | **Akseptert usikkerhet** |
| Lite kritisk + avklart | Nevnes ikke | Utenfor |

Eier velges fra en fast liste: Team 1, Team 2, Team 3, TL (teamleads), PL (projectlead) og
SG (styringsgruppen). Styringsgruppen er med fordi flere hypoteser reelt eies der — om
KraftCERT sier ja, om kostnad forsvarer gevinst, om NVE samtykker — og en arbeidsgruppe ikke
kan levere dem.
Eier er den som er ansvarlig for å **drive hypotesen i mål internt**, ikke den som tar
beslutningen eksternt — H-14 eies av den som følger opp NVE, ikke av NVE.

Listen ligger i `EIERE` i `index.html`, ikke som CHECK i databasen. Teamnavn endrer seg midt
i et prosjekt, og da skal en omdøping ikke kreve en migrasjon. Verdier som ikke finnes i
listen blir stående og vises som «(ukjent)» i stedet for å forsvinne stille.

Hver hypotese i «Må avklares» skal ha **eier** og **frist**. Uten det er listen en samling
bekymringer, ikke oppgaver, og da kan ikke styringsgruppen beslutte på den. Grensesnittet
teller opp hvor mange som mangler det.

Den tredje raden er den som er lett å hoppe over, og den som skiller en moden anbefaling fra
en tynn en: si eksplisitt hva dere har valgt å ikke finne ut av. Står det ikke der, ser det
ut som dere ikke tenkte på det.

## Å vurdere

Skalaen er **1–10** på begge akser. Den har bevisst ikke noe midtpunkt: 5,5 finnes ikke som
valg, så hver deltaker må velge side. Kvadrantgrensen går derfor mellom 5 og 6.

Ved siden av tallene står **«Vet ikke»**. Den skiller «jeg mener usikkerheten er lav» fra
«jeg har ikke grunnlag for å mene noe» — to helt ulike utsagn som før så like ut, fordi den
uten grunnlag enten måtte gjette eller tie. «Vet ikke» teller ikke i snittet, men telles og
vises for seg: «3 vet ikke» på kortet, og en stiplet ring rundt punktet i matrisen som blir
tydeligere jo større del av rommet som ikke kunne svare.

Har ingen av dem som svarte noe tallgrunnlag, merkes hypotesen **«Ingen kan svare»** og får
sitt eget filter. Den er ikke uvurdert — den er ubesvarlig med kunnskapen i rommet, og
krever at noen henter inn kunnskap utenfra. Det er en annen oppgave enn å vurdere.

To måter å vurdere på, begge like gyldige:

- **Skalaen på kortet** — klikk et trinn. Lagres med én gang.
- **Dra i matrisen** — bytt til «Min vurdering», dra punktene dit du mener de hører hjemme,
  og trykk **Bekreft**. Punktene snapper til hele trinn. Et dratt punkt er stiplet og teller
  ikke før det er bekreftet. Piltastene flytter det valgte punktet for den som ikke bruker mus.

«Alles snitt» er lesevisning og kan ikke dras i — gjennomsnittet er ikke én persons å flytte.
I «Min vurdering» vises bevisst **ikke** hvor gruppen ligger. Ser du flertallet mens du
stemmer, havner du der selv, og da måler dere enighet i stedet for vurdering.

Grensen for «Må avklares» går ved snitt over 5,5 på begge akser.

**«Uenige»** flagges når rommet er delt om hvilken kvadrant hypotesen hører til: minst 30 %
på hver side av grensen, og minst 4 trinn mellom ytterpunktene. Målet er bevisst ikke
avstanden mellom ytterpunktene alene — med 16 deltakere flagget det 100 % av tilfellene der
én enkelt person avvek, og da mister merket verdi. Tallene står i `ANDEL`, `SPRIK` og
`MIN_STEMMER` i `index.html`.

**Storskjerm** skjuler alt annet enn matrisen og «Må avklares», tvinger visningen til alles
snitt og forstørrer teksten. Beregnet på projektor mens rommet vurderer fra hver sin PC.
Escape avslutter. «Må avklares» er en sortert liste, ikke en
beslutning — se hvor mange som havner der før dere lover å teste alle.

## Slik fungerer tilgangen

- Ingen brukerkontoer. Deltakerne skriver inn en felles **passkode** og navnet sitt.
- Alle tabeller har RLS slått på uten policies, så de kan ikke leses eller endres direkte via API-et.
- All tilgang går gjennom sju databasefunksjoner (`get_board`, `join_workshop`, `add_hypothesis`,
  `publish_hypothesis`, `update_hypothesis`, `delete_hypothesis`, `rate_hypothesis`). Alle krever passkoden.
- Ved innlogging får hver deltaker et tilfeldig token som lagres i nettleseren. Skriving krever
  token, så ingen kan endre andres vurderinger.
- **Slette kan du bare det du selv har lagt inn.** Knappen vises ikke på andres hypoteser, og
  databasen avviser forsøket uansett klient. I et rom med seksten deltakere er ett feiltrykk nok
  til å fjerne noen andres arbeid, og angrefrist finnes ikke.
- **Kladd er personlig.** En hypotese kan lagres uten å publiseres. Da ser bare du den, den får
  ikke nummer, og ingen kan vurdere den. Nummeret tildeles i det du trykker «Publiser». Poenget
  er at en halvtenkt formulering ikke skal samle vurderinger før den er ferdig — snittet bærer
  preg av teksten den ble gitt på. Kladd skrives heller ikke til Confluence.
- Passkoden lagres bare som bcrypt-hash i databasen.
- Supabase-rådgiveren melder at funksjonene er `SECURITY DEFINER` og kan kalles anonymt.
  Det er tilsiktet: funksjonene er selve tilgangskontrollen.

`config.js` inneholder prosjektets URL og publishable key. Den er ment å være offentlig.

## Publisere på GitHub Pages

1. Legg filene i et repo.
2. Settings → Pages → Deploy from a branch → `main` / `(root)`.
3. Del adressen og passkoden med deltakerne. Ikke legg koden i repoet.

## Ny workshop eller ny passkode

### Bytte kode

```sh
./supabase/ny_kode.sh              # foreslår koder på formatet XXXX-XXXX
./supabase/ny_kode.sh ABCD-2345    # setter den
```

Skriptet gjør koden om til store bokstaver før den hashes. Det er ikke kosmetikk:
`workshop_by_code` slår opp på `upper(btrim(koden))`, så en hash laget av små bokstaver gjør
at ingen kommer inn. Det er den enkleste måten å låse seg selv ute på.

**Hvor kort kan koden være?** Databasen bruker rundt 18 ms på å verifisere ett forsøk, altså
54 gjetninger i sekundet per tråd. `join_workshop` har ingen sperre mot mange forsøk, og
prosjekt-URL-en ligger offentlig i `config.js`:

| Lengde | Muligheter | Tid å knekke ved ~500 forsøk/sek |
|---|---|---|
| Et ord som NORDLYS | 1 | umiddelbart |
| 4 tegn | 1 mill. | 35 minutter |
| 5 tegn | 34 mill. | 9 timer |
| 6 tegn | 1,1 mrd. | 12 dager |
| **8 tegn (XXXX-XXXX)** | **1,1 bill.** | **35 år** |

Skriptet lager koder på formatet `XXXX-XXXX`, nekter koder under seks tegn, og bruker et
alfabet uten I, O, 0 og 1 slik at koden kan leses opp uten at noen skriver feil.

Å øke bcrypt-kostnaden er ikke gratis her: `workshop_by_code` kjører ved **hvert** RPC-kall,
også hver `get_board` fra pollingen. Seksten deltakere som poller hvert fjerde sekund gir
fire bcrypt i sekundet. På kostnad 8 er det rundt 7 % av en kjerne, på kostnad 10 blir det
fire ganger så mye.

**Bytt kode før du sender den ut, ikke underveis.** Alle som er innlogget blir logget ut, og
når de logger inn igjen oppretter `join_workshop` en *ny* deltaker. De gamle vurderingene
blir liggende igjen som en usynlig ekstra stemme i snittet.

### Manuelt i SQL Editor

Kjør i Supabase SQL Editor:

```sql
-- ny workshop
insert into public.workshops (name, code_hash)
values ('Navn på workshop', extensions.crypt('NY-KODE', extensions.gen_salt('bf', 8)));

-- bytt kode på eksisterende
update public.workshops
set code_hash = extensions.crypt('NY-KODE', extensions.gen_salt('bf', 8))
where name = 'Nordlys forprosjekt – workshop';
```

Koder skrives med store bokstaver; siden gjør om det deltakerne skriver til store bokstaver.

## Live oppdatering

Siden poller `get_board` hvert fjerde sekund, så vurderinger fra andre dukker opp uten at
noen trenger å laste siden på nytt. Intervallet styres av `pollMs` i `config.js`. Vi bruker
polling og ikke Supabase Realtime fordi tabellene er stengt med RLS uten policies — realtime
ville krevd at de åpnes, og det er selve tilgangsmodellen.

Lista bygges bare på nytt når dataene faktisk har endret seg, og fokus settes tilbake etter
rendering. Uten de to mister du markøren midt i en vurdering hvert fjerde sekund.

## Innhold

**Dette repoet er offentlig, og hypotesetekstene ligger ikke i det.**

GitHub Pages krever offentlig repo. Migrasjonene som inneholder selve hypotesene —
`0003`, `0005`, `0006` og `0008` — er derfor utelatt via `.gitignore`. Til sammen er det
rundt 64 setninger som beskriver hvilke deler av Nordlys som er uverifisert, og samlet er
det et kart over svakhetene i et kraftsektorinitiativ.

Repoet inneholder **verktøyet**. Dataene ligger i Supabase, bak passkoden. Filene ligger
lokalt hos den som kjører migrasjonene, og må deles på annen måte enn gjennom dette repoet.

Den som kloner repoet får et fullt fungerende skjema gjennom `supabase/reparer.sql`, men et
tomt register.

Hold hypotesene på overordnet nivå. Ikke legg inn konkrete sårbarheter, navngitte selskapers
sikkerhetsnivå eller annen informasjon som kan være sensitiv etter kraftberedskapsforskriften.

## Hypotesene fra forprosjektet

`0003_seed_forprosjekt.sql` legger inn de 21 hypotesene som er utledet fra åpne punkter i
`docs/forprosjekt`, de juridiske vurderingene og styringsgruppereferatene i `Team-Nordlys`.
De legges inn **uten vurderinger** — kritikalitet og usikkerhet er det workshopen som setter.

Kjør migrasjonene i rekkefølge i Supabase SQL Editor. Workshopen må finnes først; skriptet
feiler med en tydelig melding hvis navnet ikke stemmer. Det er idempotent og kan kjøres på
nytt uten å lage duplikater.

Hypotesene vises som lagt inn av «Forprosjektdokumentasjonen». Det er en pseudodeltaker med
en tilfeldig token-hash som ikke matcher noe utstedt token, så ingen kan opptre som den.

### Hvorfor akkurat fire typer

En type er verdt å ha bare hvis en tynn eller tom kategori i seg selv er et funn du må handle
på. Testet mot det kriteriet:

| Type | Spørsmålet | Hvem eier det i organisasjonen |
|---|---|---|
| Verdi | Vil de faktisk dele og bruke det? | **ingen arbeidsgruppe** |
| Gjennomførbarhet | Kan vi bygge det? | Gruppe 2 |
| Levedyktighet | Hvem eier, drifter, finansierer? | Gruppe 1 og styringsgruppen |
| Aksept | Må noen utenfor godta det? | Gruppe 1, uten mandat |

At Verdi er tynnest er ikke tilfeldig: Gruppe 1 eier styring, Gruppe 2 teknikk og Gruppe 3
testing og sikkerhet. Ingen eier spørsmålet om noen faktisk vil bruke løsningen.

Det er også grunnen til at typene ikke følger arbeidsgruppene eller agendaens fem
fagområder: en inndeling som speiler organisasjonskartet kan aldri vise hva
organisasjonskartet mangler. Hvem som gjør jobben ligger i **eier**-feltet.

«Tilpasningsevne» ble prøvd som femte type og fjernet igjen i `0008`. Det som lå der var
enten feilplassert — H-17, at det finnes en plan B uten KraftCERT, påvirker anbefalingen nå
og er levedyktighet — eller «viktig senere», som matrisen allerede uttrykker gjennom lav
kritikalitet.

## Filer

- `index.html` – hele appen
- `config.js` – Supabase-URL og publishable key
- `AGENTS.md` – arbeidsinstruks for agenter: migreringsrutine, testing, konvensjoner
- `supabase/migrations/0001_init.sql` – tabeller og funksjoner
- `supabase/migrations/0002_kilde.sql` – kildefelt på hypotesene
- `supabase/migrations/0003_seed_forprosjekt.sql` – de 21 hypotesene fra forprosjektet
- `supabase/migrations/0004_eier_frist.sql` – eier og frist
- `supabase/migrations/0005_rydd_typer.sql` – skiller eksternt regelverk fra eget sikkerhetsarbeid
- `supabase/migrations/0006_tilpasningsevne.sql` – femte type
- `supabase/migrations/0007_skala_1_10.sql` – utvider skalaen fra 1–5 til 1–10
- `supabase/migrations/0008_fire_typer.sql` – fire typer, og hypotesene om pilot og videreføring
- `supabase/migrations/0009_status_belegg.sql` – belegg og sporing på statusendringer
- `supabase/migrations/0010_confluence_sync.sql` – automatisk skriving til Confluence
- `supabase/migrations/0011_passkode.sql` – passkoden som hash
- `supabase/migrations/0012_kladd_og_eierskap.sql` – kladd før publisering, og sletting bare av egne
- `supabase/migrations/0013_eierskap_og_to_nye.sql` – eier fra H-lista, driftsevne og mesh uten anker, og splitt av kostnad/alternativ
- `supabase/migrations/0014_vet_ikke.sql` – «vet ikke» (0) som eget svar ved siden av 1–10
- `supabase/reparer.sql` – bringer skjemaet i riktig tilstand uansett utgangspunkt
- `supabase/sjekk_status.sql` – viser hvilke migrasjoner som er anvendt, endrer ingenting
- `supabase/kjor.sh` – kjører de to over mot Supabase via docker
- `supabase/ny_kode.sh` – setter ny passkode

Migrasjoner kjøres med Supabase CLI (`supabase db push`), ikke ved å lime inn i SQL Editor.
Se `AGENTS.md` for rekkefølge og fallgruver — migrasjonshistorikken i fjernbasen er ikke i
synk med numreringen her, så `db push` krever et `migration repair` først.

### Når noe ikke stemmer

`supabase/reparer.sql` bringer databasen til riktig tilstand uansett hvilke migrasjoner som
er kjørt før. Den legger til kolonner som mangler, dropper **alle** gamle utgaver av
funksjonene og bygger dem opp i endelig form, retter begrensningene og ber PostgREST lese
skjemaet på nytt. Data røres ikke. Trygg å kjøre flere ganger.

Den er nødvendig fordi migrasjonene 0002, 0004, 0005 og 0006 endrer signaturen på de samme
funksjonene, og hver av dem dropper bare den utgaven den forventer å finne. Hoppes én over,
blir gamle utgaver liggende igjen som overlast, og PostgREST melder at funksjonen ikke
finnes selv om noe med samme navn er der.

```sh
echo 'postgresql://postgres.xxxx:PASSORD@...pooler.supabase.com:5432/postgres' > ~/.nordlys-db
chmod 600 ~/.nordlys-db
./supabase/kjor.sh          # kjører reparer.sql, så statussjekken
```

Skriptet kjører psql i docker, så ingenting må installeres. Tilkoblingsstrengen sendes som
miljøvariabel inn i containeren og havner verken i prosesslisten eller i terminalloggen.
Bruk «Session pooler» (port 5432) — transaction pooler på 6543 er ikke ment for DDL.

Merk at `reparer.sql` **ikke** legger inn de 21 hypotesene. Er registeret tomt, kjør
`0003_seed_forprosjekt.sql` i tillegg.

**Etter DDL-endringer må PostgREST laste skjemaet på nytt.** Supabase gjør det som regel
automatisk, men ikke alltid. Får du «Could not find the function ... in the schema cache»,
kjør:

```sql
notify pgrst, 'reload schema';
```

Den feilen har to årsaker med identisk melding: migrasjonen er ikke kjørt, eller den er kjørt
men cachen er gammel. `supabase/sjekk_status.sql` skiller dem — den viser hvilke migrasjoner
som faktisk er anvendt, og endrer ingenting.
RPC-ene har default-verdier på de nye parametrene, så en klient som ennå ikke er oppdatert
fortsetter å virke — SQL og publisering trenger ikke skje samtidig.
