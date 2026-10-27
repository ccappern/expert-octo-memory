# Hypoteser i Nordlys-forprosjektet

Her er hypotesene samlet i en enkel og lesbar oversikt, gruppert etter leveranse.

Forprosjektet skal i hovedtrekk svare på tre spørsmål:

- **Har Nordlys dokumentert verdi?**
- **Er Nordlys gjennomførbart?**
- **Er det grunnlag for å gå videre?**

Les gjennom samtlige hypoteser og vurder dem. Noter gjerne ned de du synes er viktigst.

> **Dette er forslag, ikke vedtak.** Ingenting på denne siden er besluttet. Hypotesene er
> vår måte å teste om leveransene er gode nok — og de skal utfordres.

---

## Hvor mange, og hvorfor akkurat disse

Registeret startet på 28 hypoteser. Det er kuttet til **9** som skal behandles nå.
Begrunnelsen for kuttet er at en hypotese fortjener plass bare hvis **anbefalingen til
styringsgruppen endrer seg når den viser seg å være feil**.

Tre bunker falt bort på det kriteriet:

| Bunke | Hva skjedde |
|---|---|
| **Premisser** | Kritiske, men ikke usikre. Skrives ned som forutsetninger, utredes ikke. |
| **Hovedprosjektets jobb** | Ingeniørspørsmål som endrer *hvordan* man bygger, ikke *om* man skal. |
| **Slått sammen** | Flere hypoteser stilte samme spørsmål fra ulik vinkel. |

De 19 som er tatt ut står nederst på siden. Ingen er slettet — de kan hentes tilbake.

---

## De 9 hypotesene

Hver hypotese har to deler: **påstanden** vi tror er sann, og **kriteriet** som sier når vi
vet om den holder. Et kriterium som ikke kan slå begge veier er ikke et kriterium.

### 1. Målbilde, brukerbehov og omfang

*Fokus: Har vi identifisert riktig problem, målgruppe og behov?*

**H-28** — Dagens løsninger betjener bare den delen av sektoren som har infrastruktur,
kompetanse og bemanning til å drifte dem. Nordlys når resten: lav etableringsterskel,
utvidbarhet utover cybersikkerhetsdata, og uten at lav terskel forutsetter at noen andre
eier dataene dine.
*Vi vet det når:* et notat tallfester hvor stor del av KBO-enhetene som står utenfor enhver
delingsordning i dag, sammenligner Nordlys mot MISP (som gjest hos KraftCERT og som egen
instans) på etableringsterskel og dataeierskap, og viser minst én ikke-CTI datatype
sektoren trenger som MISPs datamodell ikke bærer.
*Motbevis:* de små aktørene er godt nok betjent av en gjestekonto hos KraftCERT, og den
sentraliseringen er en pris de aksepterer.

**H-29** — Deltakerne oppdager og handler på delte indikatorer i tide bare hvis plattformen
varsler dem aktivt i kanalen de allerede står i. En løsning som krever at de selv logger inn
og sjekker, blir valgt bort til fordel for Teams eller e-post. Varselvolumet må samtidig
være lavt nok til at varslene ikke ignoreres.
*Vi vet det når:* minst 2 av 3 deltakende selskaper i en pilot reagerer på et relevant
varsel innen én time, varselvolum og relevans per mottaker er målt, og drifts- og
OT-personell har brukt grensesnittet under en øvelse — ikke bare i etterkant.

### 2. Validerte bruksområder og verdiforslag

*Fokus: Skaper Nordlys faktisk verdi?*

**H-01** — Sikkerhetsanalytikere vil faktisk dele egne observasjoner utenfor egen
virksomhet, og ikke bare konsumere andres.
*Vi vet det når:* operativt personell i minst tre selskaper har beskrevet hva de konkret
ville delt, og hva som stopper dem.

**H-02** — Et delt situasjonsbilde reduserer tiden fra en lokal observasjon oppstår til
andre aktører kan iverksette tiltak.
*Vi vet det når:* vi har en baseline fra 2–3 historiske hendelser, og det samme forløpet er
målt i PoC-demoen.

**H-30** — Delte indikatorer er presise og ferske nok til at mottakeren kan handle på dem
uten å verifisere dem selv først.
*Vi vet det når:* andelen delte indikatorer som faktisk førte til et tiltak er målt i en
pilot, og analytikerne har vurdert treffsikkerheten.
*Motbevis:* indikatorene må verifiseres manuelt uansett — da er tidsgevinsten i H-02 borte.

### 3. Foreslått målarkitektur og teknisk retning

*Fokus: Er løsningen teknisk gjennomførbar?*

**Ingen hypoteser.** Alle de tekniske hypotesene er flyttet til hovedprosjektet. De endrer
hvordan Nordlys bygges, ikke om det bør bygges — og de er dermed ikke en forutsetning for
go/no-go.

*Er dere uenige i det, er denne leveransen det første stedet å melde fra.*

### 4. Sikkerhetsmessige, juridiske og regulatoriske avklaringer

*Fokus: Er løsningen lovlig og sikker?*

**H-14** — Kraftsensitiv informasjon kan deles innenfor kraftberedskapsforskriften § 6-2 og
§ 6-3 og konkurranseloven § 10, og NVE støtter løsningen.
*Vi vet det når:* NVE har gitt tilbakemelding på et utkast til klassifiserings- og
delingsprofil, og en juridisk analyse av den konkurranserettslige avgrensningen foreligger.

### 5. Foreslått styrings-, eierskaps- og driftsmodell

*Fokus: Hvordan skal Nordlys organiseres og driftes?*

**H-11** — KraftCERT påtar seg rollen som tillitsanker og identitetsutsteder — eller det
finnes en gjennomførbar alternativ forvaltningsmodell, med rom for å legge til flere
likestilte ankre som NVE og NSM senere.
*Vi vet det når:* KraftCERT har gitt skriftlig tilbakemelding før styringsgruppemøte #3, og
alternative modeller er utredet og vurdert før go/no-go.

**H-26** — Hver virksomhet har kapasitet til selv å drifte en node og en Varde i daglig
drift.
*Vi vet det når:* hver deltaker har bekreftet driftskapasitet, eller det foreligger en
avklart modell med driftsleverandør for de mindre aktørene.

### 6. Forankring, forretningsgrunnlag og gjennomføringsplan

*Fokus: Er det vilje og evne til å gå videre?*

**H-22** — Minst tre virksomheter vil delta i en pilot på de vilkårene vi kan tilby, og
løsningen kan testes i et realistisk miljø uten uakseptabel risiko for
driftskontrollsystemene.
*Vi vet det når:* tre selskaper har bekreftet skriftlig at de stiller med ressurser og
testmiljø, og en risikovurdering av pilotoppsettet er gjennomført og akseptert av
sikkerhetsansvarlig i de deltakende selskapene.

### 7. Beslutningsgrunnlag og anbefaling for videreføring

Denne leveransen er en syntese av de øvrige og skal besvare:

- Har Nordlys dokumentert verdi?
- Er Nordlys gjennomførbart?
- Er risikoen akseptabel?
- Finnes det tilstrekkelig støtte og finansiering?
- Bør styringsgruppen anbefale go eller no-go?

---

## Fordelingen, og hva den avslører

| Leveranse | Hypoteser | Antall |
|---|---|---|
| 1. Målbilde, brukerbehov og omfang | H-28, H-29 | 2 |
| 2. Validerte bruksområder og verdiforslag | H-01, H-02, H-30 | 3 |
| 3. Målarkitektur og teknisk retning | — | **0** |
| 4. Sikkerhet, juss og regulatorisk | H-14 | 1 |
| 5. Styrings-, eierskaps- og driftsmodell | H-11, H-26 | 2 |
| 6. Forankring og forretningsgrunnlag | H-22 | 1 |
| 7. Beslutningsgrunnlag | *syntese* | — |

**To ting er verdt å merke seg.**

Fem av ni hypoteser handler om verdi og målbilde. Det er der usikkerheten vår er størst —
men det betyr også at vi tester verdiforslaget hardere enn vi tester om vi klarer å levere.

Leveranse 3 har ingen hypoteser i det hele tatt, og leveranse 4 og 6 har én hver. En
leveranse uten hypoteser er enten ikke kritisk for go/no-go, eller så mangler det en
hypotese der. **Begge deler er verdt å si høyt.**

---

## Hypoteser som er tatt ut

Ingen er slettet. Alle kan hentes tilbake hvis vurderingen var feil.

### Premisser — kritiske, men ikke usikre

Disse legges til grunn og skrives inn i rapporten som forutsetninger.

| | |
|---|---|
| H-05 | Verdikjeden motta → klassifisere → distribuere kan demonstreres ende-til-ende. |
| H-07 | TLP-regler kan håndheves teknisk, ikke bare organisatorisk. |
| H-27 | Deling mellom eksisterende deltakere fortsetter selv om tillitsankeret blir utilgjengelig. |

### Hovedprosjektets jobb — endrer *hvordan*, ikke *om*

| | |
|---|---|
| H-06 | Bounded gossip skalerer til ca. 400 deltakere uten lineær vekst i forbindelser. |
| H-08 | Løsningen oppnår tilstrekkelig lav forsinkelse og rask distribusjon. |
| H-09 | Rollebasert tilgangsstyring og TLP-klarering kan implementeres før pilot. |
| H-10 | Onboarding fungerer også når KraftCERT ikke er tilknyttet samme Varde. |
| H-18 | Flere tillitsankre kan legges til senere uten å omarkitektere. |
| H-19 | Tredjepartsplugins kan tillates uten å svekke sikkerheten. |
| H-21 | Arkitekturen kan tilpasses gradert informasjon dersom det blir aktuelt. |
| H-23 | Løsningen kan testes i realistisk miljø uten uakseptabel risiko. *(slått inn i H-22)* |

### Slått sammen med andre

| | Gikk inn i |
|---|---|
| H-03 | Løsningen gir verdi uten å øke alert fatigue. | H-29 |
| H-04 | Drifts- og OT-personell vil bruke løsningen aktivt under hendelser. | H-29 |
| H-13 | Kostnaden er lav nok til at også mindre aktører kan delta. | H-28 |
| H-15 | Juridisk enhet med begrenset ansvar kan etableres. | H-11 |
| H-16 | Sanntidsdeling er forenlig med konkurranseloven og Statnetts TSO-rolle. | H-14 |
| H-17 | Alternativ forvaltningsmodell finnes hvis KraftCERT takker nei. | H-11 |
| H-20 | Nye medlemmer kan tas opp uten reforhandling av konsortieavtalen. | H-11 |
| H-24 | Finansiering og eierskap for neste fase kan etableres. | H-22 |

### Under vurdering

| | |
|---|---|
| H-12 | Selskapene signerer konsortieavtalen og binder seg til et minimum ressursbidrag. **Formuleringen stemmer ikke, og hypotesen er holdt utenfor til den er rettet.** |

---

## Hva som skjer med disse i workshopen

1. **Individuell vurdering.** Hver deltaker markerer hver hypotese som
   ✅ må avklares før go/no-go · 🟡 bør avklares dersom mulig · ⚪ kan vente til neste fase.
2. **Samlet prioritering.** Resultatet summeres, og rommet skjærer ned til de som faktisk
   må være avklart før styringsgruppen kan ta stilling.
3. **Gruppearbeid.** Er hypotesen formulert godt nok? Kan den forenkles? Hvordan skal den
   valideres? Og: mangler det en hypotese?
4. **Felles gjennomgang.** Gruppene presenterer, og vi fyller ut hvem som eier hva og hva
   neste steg er.

Resultatet er en liste over hva som må avklares, av hvem, innen når — og den er det
styringsgruppen trenger for å kunne ta stilling til go/no-go innen 31.03.2027.
