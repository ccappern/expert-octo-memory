# Hypoteseregisteret — full oversikt

Alle hypoteser som har vært i registeret, med status. Per 27.10.2026, etter workshopen 26.10.

| | Antall |
|---|---|
| Aktive, vurdert av rommet | 9 |
| Aktiv, holdt utenfor | 1 |
| Arkivert | 19 |
| Testrader | 2 |
| **Totalt i basen** | **31** |
| Foreslått nytt, ikke lagt inn | 9 |

Ingenting er slettet. Alle arkiverte beholder teksten sin og kan hentes tilbake.

---

## 1. Aktive hypoteser

Vurdert av 17 deltakere. **Kritisk** betyr at flertallet markerte ✅ «må avklares før
go/no-go».

| # | Hypotese | Leveranse | ✅ | 🟡 | ⚪ | Status |
|---|---|---|---|---|---|---|
| H-01 | Analytikere vil dele egne observasjoner, ikke bare konsumere andres | 6 Brukerbehov | **15** | 1 | 0 | **Kritisk** · formulering utfordret |
| H-14 | Kraftsensitiv info kan deles innenfor regelverket, og NVE støtter | 5 Juridisk | **12** | 1 | 1 | **Kritisk** · bør splittes i tre |
| H-02 | Delt situasjonsbilde reduserer tiden til tiltak | 1 Målbilde | **11** | 2 | 3 | **Kritisk** · bør omformuleres |
| H-11 | KraftCERT som tillitsanker, eller alternativ forvaltningsmodell | 4 Styring | **10** | 4 | 0 | **Kritisk** · formulering godkjent |
| H-22 | Tre virksomheter i pilot, testbart uten uakseptabel risiko | 2 Forankring | **8** | 4 | 2 | **Kritisk** · formulering godkjent |
| H-26 | Hver virksomhet kan drifte egen node og Varde | 4 Styring | 7 | 3 | 4 | **Uavgjort** — 7 mot 7 |
| H-29 | Aktiv varsling i kanalen brukerne allerede står i | 1 Målbilde | 6 | 2 | 6 | Ikke kritisk · for lang (53 ord) |
| H-28 | Ingen dagens løsning når resten av sektoren | 1 Målbilde | 3 | 7 | 3 | Ikke kritisk · for lang (40 ord) |
| H-30 | Indikatorer er presise og ferske nok til å handle på | 1 Målbilde | 3 | 7 | 2 | Ikke kritisk · formulering godkjent |

**H-26 er det eneste uavgjorte.** 7 mot 7 er ikke en konklusjon — den må avgjøres eksplisitt.

### Holdt utenfor

| # | Hypotese | Leveranse | Status |
|---|---|---|---|
| H-12 | Juridisk enhet med ansvarsbegrensning, selskapene binder seg til konsortieavtalen | 2 Forankring | **Aktiv i basen, men tatt ut av workshopen.** Formuleringen stemmer ikke. Må rettes eller arkiveres. |

---

## 2. Arkiverte hypoteser

Kuttet fra 28 til 9 før workshopen. Kriteriet var: *en hypotese fortjener plass bare hvis
anbefalingen til styringsgruppen endrer seg når den viser seg å være feil.*

### Premisser — kritiske, men ikke usikre

Legges til grunn og skrives inn i rapporten som forutsetninger. De utredes ikke.

| # | Hypotese | Leveranse |
|---|---|---|
| H-05 | Verdikjeden motta → klassifisere → distribuere kan demonstreres ende-til-ende | 3 Teknisk |
| H-07 | TLP håndheves teknisk: AMBER+STRICT forlater ikke noden | 3 Teknisk |
| H-27 | Deling fortsetter selv om tillitsankeret er utilgjengelig | 3 Teknisk |

### Hovedprosjektets jobb — endrer *hvordan*, ikke *om*

Ingeniør- og omfangsspørsmål. Ingen av dem endrer anbefalingen om å gå videre.

| # | Hypotese | Leveranse |
|---|---|---|
| H-06 | Bounded gossip skalerer til 400 peers uten lineær vekst i forbindelser | 3 Teknisk |
| H-08 | Ende-til-ende-latens under ett sekund ved direktelevering | 3 Teknisk |
| H-09 | RBAC og TLP-klarering per operatør kan ferdigstilles før pilot | 3 Teknisk |
| H-10 | Onboarding fungerer uten at KraftCERT er på samme Varde | 3 Teknisk |
| H-18 | Flere likestilte tillitsankre kan legges til senere uten omarkitektur | 3 Teknisk |
| H-19 | Tredjepartsplugins kan tillates uten å svekke sikkerheten | 5 Juridisk |
| H-21 | Arkitekturen kan tilpasses gradert informasjon etter sikkerhetsloven | 5 Juridisk |

### Slått sammen med en annen hypotese

| # | Hypotese | Gikk inn i |
|---|---|---|
| H-03 | Verdi uten å øke alert fatigue og falske positive | **H-29** |
| H-04 | Drifts- og OT-personell bruker grensesnittet under hendelsen | **H-29** |
| H-13 | Kostnad per deltaker lav nok for de minste aktørene | **H-28** |
| H-15 | Juridisk enhet med ansvarsbegrensning for feilaktig delt info | **H-11** |
| H-16 | Sanntidsdeling forenlig med konkurranseloven § 10 og Statnetts TSO-rolle | **H-14** |
| H-17 | Alternativ forvaltningsmodell hvis KraftCERT takker nei | **H-11** |
| H-20 | Nye medlemmer uten reforhandling av konsortieavtalen | **H-11** |
| H-23 | Testbart i realistisk miljø uten uakseptabel risiko | **H-22** |
| H-24 | Finansiering og eierskap for neste fase før forprosjektet avsluttes | **H-22** |

### Testrader

Ikke ekte hypoteser. Kan slettes permanent.

| # | Tekst |
|---|---|
| H-25 | «Test» |
| *uten nummer* | «test» |

---

## 3. Foreslått nytt — ikke lagt inn

Fra gruppearbeidet og utledet av gruppesvarene. **Ingen er besluttet.**

| # | Hypotese | Opphav | Status |
|---|---|---|---|
| N-01 | Virksomhetene kan bli enige om felles kriterier for hva som skal deles | Gruppe 2, etterlyst av tre andre | Bekreftet — sterkeste signal |
| N-02 | CSOC er primærbruker, IKT-sikkerhetskoordinator sekundærbruker | Gruppe 2 | Bekreftet |
| N-03 | De minste KBO-enhetene kan delta uten egen driftskapasitet | Utledet av H-26 og H-28 | Må bekreftes |
| N-04 | Delte indikatorer kan merkes med konfidensnivå mottakeren stoler på | Utledet av H-30 | Må bekreftes |
| N-05 | NVE eller NSM kan tre inn som tillitsanker hvis KraftCERT ikke kan | Utledet av H-11 | Må bekreftes |
| H-28a | En vesentlig del av KBO-enhetene står utenfor enhver delingsordning | Omskriving | Gruppene ba om det |
| H-28b | Nordlys senker terskelen uten at andre må eie dataene dine | Omskriving | Gruppene ba om det |
| H-29a | Brukerne reagerer i tide bare ved varsling i kjent kanal | Omskriving | Gruppene ba om det |
| H-29b | Varselvolumet kan holdes lavt nok til at varslene ikke ignoreres | Omskriving | Gruppene ba om det |

Full tekst med kriterier og motbevis står i `oppsummering-2026-10-26.md`.

---

## Fordeling per leveranse

Aktive hypoteser, etter leveransene i workshopagendaen.

| Leveranse | Aktive | Arkivert |
|---|---|---|
| 1. Målbilde, brukerbehov og omfang | H-02, H-28, H-29, H-30 | H-03, H-04 |
| 2. Validerte bruksområder og verdiforslag | H-22 *(+H-12 utenfor)* | H-23, H-24 |
| 3. Målarkitektur og teknisk retning | **ingen** | H-05–H-10, H-18, H-27 |
| 4. Sikkerhet, juss og regulatorisk | H-14 | H-16, H-19, H-21 |
| 5. Styrings-, eierskaps- og driftsmodell | H-11, H-26 | H-13, H-15, H-17, H-20 |
| 6. Forankring og forretningsgrunnlag | H-01 | — |
| 7. Beslutningsgrunnlag | *syntese* | — |

**Leveranse 3 er tom.** Åtte hypoteser er flyttet dit fra — alle til hovedprosjektet eller
som premiss. Er det riktig at teknisk gjennomførbarhet ikke trenger å avklares før go/no-go,
er leveransen reelt ferdig. Er det ikke riktig, mangler det en hypotese der.

**Leveranse 2 og 6 har én hver.** Begge bærer tunge spørsmål for go/no-go — vilje til å
delta, og vilje til å finansiere — på ett enkelt punkt hver, etter at H-13, H-24 og H-12
falt bort.

---

## Åpne beslutninger

1. **H-12** — rettes eller arkiveres?
2. **H-26** — 7 mot 7. Kritisk eller ikke?
3. **H-14** — splittes i tre før eier settes?
4. **H-02** — omformuleres etter Gruppe TAIDs forslag?
5. **H-01** — forplikte virksomheten eller analytikeren?
6. **N-01 til N-05** — hvilke legges inn?
7. **H-28 og H-29** — deles i to?
8. **H-25 og den uten nummer** — slettes permanent?

---

## 4. Full tekst — påstand og kriterium

Ordrett fra registeret. Kriteriet er halve hypotesen: uten det er påstanden
bare en mening.

### Aktive

**H-01** · **Kritisk** — 15 av 16 ✅

*Vi tror at* sikkerhetsanalytikere faktisk vil dele egne observasjoner utenfor egen virksomhet, og ikke bare
konsumere andres

*Vi vet det når* operativt personell i minst tre selskaper har beskrevet hva de konkret ville delt, og hva som
stopper dem

**H-14** · **Kritisk** — 12 av 14 ✅

*Vi tror at* kraftsensitiv informasjon kan deles innenfor kraftberedskapsforskriften § 6-2 og § 6-3 og
konkurranseloven § 10, og NVE støtter løsningen

*Vi vet det når* NVE har gitt tilbakemelding på et utkast til klassifiserings- og delingsprofil, og en juridisk
analyse av den konkurranserettslige avgrensningen foreligger

**H-02** · **Kritisk** — 11 av 16 ✅

*Vi tror at* delt situasjonsbilde reduserer tiden fra en lokal observasjon oppstår til andre aktører kan
iverksette tiltak

*Vi vet det når* vi har en baseline fra 2–3 historiske hendelser, og det samme forløpet er målt i PoC-demoen

**H-11** · **Kritisk** — 10 av 14 ✅

*Vi tror at* KraftCERT påtar seg rollen som tillitsanker og identitetsutsteder — eller det finnes en
gjennomførbar alternativ forvaltningsmodell, med rom for å legge til flere likestilte ankre som
NVE og NSM senere

*Vi vet det når* KraftCERT har gitt skriftlig tilbakemelding før styringsgruppemøte #3, og alternative modeller
er utredet og vurdert før Go/No-Go

**H-22** · **Kritisk** — 8 av 14 ✅

*Vi tror at* minst tre virksomheter vil delta i en pilot på de vilkårene vi kan tilby, og løsningen kan
testes i et realistisk miljø uten uakseptabel risiko for driftskontrollsystemene

*Vi vet det når* tre selskaper har bekreftet skriftlig at de stiller med ressurser og testmiljø, og en
risikovurdering av pilotoppsettet er gjennomført og akseptert av sikkerhetsansvarlig i de
deltakende selskapene

**H-26** · Uavgjort — 7 ✅ mot 7

*Vi tror at* hver virksomhet har kapasitet til selv å drifte en node og en Varde i daglig drift

*Vi vet det når* hver deltaker har bekreftet driftskapasitet, eller det foreligger en avklart modell med
driftsleverandør for de mindre aktørene

**H-29** · Ikke kritisk — 6 ✅ mot 8

*Vi tror at* deltakerne oppdager og handler på delte indikatorer i tide bare hvis plattformen varsler dem
aktivt i kanalen de allerede står i. En løsning som krever at de selv logger inn og sjekker,
blir valgt bort til fordel for Teams eller e-post. Varselvolumet må samtidig være lavt nok til
at varslene ikke blir ignorert.

*Vi vet det når* vi i en pilot har sett at minst 2 av 3 deltakende selskaper reagerer (åpner eller kvitterer) på
et relevant varsel innen 1 time, at varselvolum og relevans per mottaker er målt, og at drift-
og OT-personell har brukt grensesnittet under en øvelse og ikke bare i etterkant. (Motbevis: de
sjekker plattformen jevnlig uten varsler, eller ignorerer varslene.)

**H-28** · Ikke kritisk — 3 ✅ mot 10

*Vi tror at* dagens løsninger betjener bare den delen av sektoren som har infrastruktur, kompetanse og
bemanning til å drifte dem. Nordlys når resten — med lav etableringsterskel, utvidbarhet utover
cybersikkerhetsdata, og uten at lav terskel forutsetter at noen andre eier dataene dine.

*Vi vet det når* et notat som (a) tallfester hvor stor del av KBO-enhetene som i dag står utenfor enhver
delingsordning, og hvorfor, (b) sammenligner Nordlys mot MISP som gjest hos KraftCERT og mot
egen MISP-instans, på etableringsterskel og på hvem som eier og ser dataene, og (c) viser minst
én ikke-CTI datatype sektoren trenger, som MISPs datamodell ikke bærer uten kjerneendring.
(Motbevis: de små aktørene er godt nok betjent av en gjestekonto hos KraftCERT, og den
sentraliseringen er en pris de aksepterer.)

**H-30** · Ikke kritisk — 3 ✅ mot 9

*Vi tror at* delte indikatorer er presise og ferske nok til at mottakeren kan handle på dem uten å verifisere
dem selv først

*Vi vet det når* i en pilot er andelen delte indikatorer som faktisk førte til et tiltak målt, og analytikerne
har vurdert treffsikkerheten. (Motbevis: indikatorene må verifiseres manuelt uansett — da er
tidsgevinsten i H-02 borte.)

**H-12** · Holdt utenfor workshopen

*Vi tror at* det kan etableres en juridisk enhet med ansvarsbegrensning der selskapene binder seg til
konsortieavtalen og et minimum ressursbidrag, og der etablerings- og driftskostnad per deltaker
er lav nok til at også de minste aktørene kan delta

*Vi vet det når* hvert selskap har gitt en intensjonsavklaring, avtaleutkastet med ansvarsbegrensning er juridisk
gjennomgått, og et business case med kostnad per deltaker, gevinstberegning og navngitt eier for
neste fase er behandlet i styringsgruppen

### Arkiverte

**H-03** · Slått inn i H-29

*Vi tror at* løsningen gir verdi uten å øke alert fatigue og andelen falske positive hos mottakerne

*Vi vet det når* volum og relevans per mottaker er målt i PoC, og analytikere har testet filtrering og terskler

**H-04** · Slått inn i H-29

*Vi tror at* drift- og OT-personell tar grensesnittet i bruk under en pågående hendelse, ikke bare i
etterkant

*Vi vet det når* driftssentralen har gjennomført en scenariobasert test på en klikkbar mockup

**H-05** · Premiss

*Vi tror at* verdikjeden motta → klassifisere → distribuere kan demonstreres ende-til-ende mellom to noder
før Go/No-Go

*Vi vet det når* en reproduserbar demo i app/deploy/two-node viser en signert hendelse i mottakers frontend

**H-06** · Hovedprosjektet

*Vi tror at* bounded gossip skalerer til 400 peers uten at antall forbindelser vokser lineært

*Vi vet det når* en simulering av 400 peers viser forbindelsesvekst og konvergenstid innenfor akseptable verdier

**H-07** · Premiss

*Vi tror at* TLP håndheves teknisk og ikke bare som anbefaling: AMBER+STRICT forlater ikke noden, og RED når
kun navngitte mottakere

*Vi vet det når* negative tester i PoC viser at forsøk på brudd avvises og spores i audit-loggen

**H-08** · Hovedprosjektet

*Vi tror at* ende-til-ende-latens holder seg under ett sekund ved direktelevering, og mesh-distribusjon
konvergerer på 3–4 gossip-runder

*Vi vet det når* latens er målt både i two-node-oppsettet og i simulert mesh

**H-09** · Hovedprosjektet

*Vi tror at* rollebasert tilgangskontroll og TLP-klarering per operatør kan ferdigstilles og testes før pilot

*Vi vet det når* RBAC-matrisen er funksjonelt testet mot TLP-nivå for hver rolle

**H-10** · Hovedprosjektet

*Vi tror at* onboarding fungerer også når KraftCERT ikke er tilknyttet samme Varde som den nye noden

*Vi vet det når* vi har avklart om begrensningen i TODO #43 påvirker PoC-scope, eller demonstrert videresending
av invitasjoner

**H-13** · Slått inn i H-28

*Vi tror at* kostnaden for etablering og årlig drift per deltaker er lav nok til at også de minste aktørene
kan delta

*Vi vet det når* business case har estimat for etablering og årlig drift per deltaker, inkludert
gevinstberegning, behandlet i styringsgruppen

**H-15** · Slått inn i H-11

*Vi tror at* det kan etableres en juridisk enhet med ansvarsbegrensning som bærer ansvaret for feilaktig delt
informasjon

*Vi vet det når* selskapsform er juridisk vurdert, og et utkast til peering-avtale med ansvarsbegrensning
foreligger

**H-16** · Slått inn i H-14

*Vi tror at* sanntidsdeling mellom konkurrerende aktører er forenlig med konkurranseloven § 10, også med
Statnetts TSO-særstilling

*Vi vet det når* en juridisk analyse fra ekstern part, eventuelt en veiledningsuttalelse fra Konkurransetilsynet,
foreligger

**H-17** · Slått inn i H-11

*Vi tror at* det finnes en gjennomførbar alternativ forvaltningsmodell dersom KraftCERT takker nei til rollen

*Vi vet det når* alternative modeller er utredet og vurdert før Go/No-Go

**H-18** · Hovedprosjektet

*Vi tror at* flere likestilte tillitsankre, som NVE og NSM, kan legges til senere uten å omarkitektere
tillitsmodellen

*Vi vet det når* en arkitekturvurdering mot ADR-0010 viser om datamodellen allerede tåler flere ankre

**H-19** · Hovedprosjektet

*Vi tror at* tredjepartsplugins kan tillates uten å svekke sikkerheten, gitt en tillits- og rettighetsmodell

*Vi vet det når* plugin-grensesnittet er trusselmodellert, og beslutningen er tatt etter PoC

**H-20** · Slått inn i H-11

*Vi tror at* nye medlemmer kan tas opp uten å reforhandle konsortieavtalen eller endre stemmefordelingen

*Vi vet det når* en opptaksmekanisme med to medlemsnivåer er utformet og prøvd mot Statkraft-scenariet på papiret

**H-21** · Hovedprosjektet

*Vi tror at* arkitekturen kan tilpasses håndtering av gradert informasjon etter sikkerhetsloven

*Vi vet det når* det er avklart om gradert informasjon er i scope, og hvis ja, foreligger en arkitekturanalyse

**H-23** · Slått inn i H-22

*Vi tror at* løsningen kan testes i et realistisk miljø uten uakseptabel risiko for driftskontrollsystemene

*Vi vet det når* en risikovurdering av pilotoppsettet er gjennomført og akseptert av sikkerhetsansvarlig i de
deltakende selskapene

**H-24** · Slått inn i H-22

*Vi tror at* finansiering og eierskap for neste fase kan etableres før forprosjektet avsluttes

*Vi vet det når* en finansieringsmodell med navngitt eier er skissert og forankret i styringsgruppen

**H-27** · Premiss

*Vi tror at* deling mellom eksisterende deltakere fortsetter selv om tillitsankeret er utilgjengelig

*Vi vet det når* en demonstrasjon der ankeret slås av, og deling mellom allerede onboardede noder fortsetter
