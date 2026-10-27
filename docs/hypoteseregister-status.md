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
