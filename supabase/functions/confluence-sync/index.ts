// Bygger opp Confluence-siden «Hypoteser» på nytt fra hypoteseregisteret.
// Kalles av databasetriggeren private.notify_confluence_sync() når hypoteser eller
// vurderinger endres (maks ett kall i minuttet), og av pg_cron hvert femte minutt
// (jobben confluence-sync-5min). Skriver bare til Confluence når innholdet er endret.
//
// Hemmeligheter (Supabase → Edge Functions → Secrets):
//   CONFLUENCE_BASE_URL   https://krafthack.atlassian.net (klassisk token)
//                         eller https://api.atlassian.com/ex/confluence/<cloudId> (scoped)
//   CONFLUENCE_EMAIL      Atlassian-kontoen API-tokenet tilhører
//   CONFLUENCE_API_TOKEN  Atlassian API-token
//   CONFLUENCE_PAGE_ID    id-en til siden som overskrives (25526273)
// Uten dem rapporterer funksjonen bare at den ikke er satt opp.
//
// Personvern: individuelle vurderinger publiseres ikke. Siden viser snitt, antall
// vurderinger og uenighetsflagget — aldri hvem som stemte hva. Det speiler at
// appen heller ikke eksporterer enkeltstemmer. Gruppeforslagene vises per gruppe
// (A/B/C/D), som ikke er en enkeltstemme — men group_ratings.satt_av hentes ikke
// engang ut: forslaget er gruppas, ikke lederens.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SKALA = 10;
const MIDT = (1 + SKALA) / 2;          // 5,5 — samme grense som i klienten
const ANDEL = 0.30;
const SPRIK = 4;
const MIN_STEMMER = 3;

const STATUS: Record<string, string> = {
  ny: "Ny", testes: "Testes", bekreftet: "Bekreftet", avkreftet: "Avkreftet",
};

// Fasilitators kvittering fra plenum (§9). «Står» er et fullt legitimt utfall og
// verdt mer i rapporten enn falsk enighet, så det skrives ut i klartekst og ikke
// som et tomt felt.
const PLENUM: Record<string, string> = {
  justert: "Justert i plenum",
  staar: "Står — rommet lever med spriket",
  eskalert: "Eskalert til styringsgruppen",
};

// konstanttidssammenligning av synk-hemmeligheten (samme mønster som i nettside)
const enc = new TextEncoder();
async function likt(gitt: string, fasit: string) {
  const [a, b] = await Promise.all([gitt, fasit].map(async (s) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)))));
  let d = a.length ^ b.length;
  for (let i = 0; i < Math.min(a.length, b.length); i++) d |= a[i] ^ b[i];
  return d === 0;
}

type Hyp = {
  id: string; nr: number; tekst: string; kriterium: string; type: string; status: string;
  leveranse: string | null; leveranse_2: string | null;
  kilde: string; eier: string; frist: string | null;
  status_notat: string; status_endret: string | null; status_av: string | null;
  created_at: string; workshop_id: string;
  // 0021: det trakten endte på. endelig_k/u er gjeldende plassering fra det
  // øyeblikket fasilitator åpner plenum.
  i_gruppearbeid: boolean;
  endelig_k: number | null; endelig_u: number | null; gruppesprik: boolean;
  plenum_utfall: string | null; plenum_notat: string;
};
type Lev = { slug: string; nr: number; label: string };
type Rate = { hypothesis_id: string; participant_id: string; k: number | null; u: number | null };
type Grp = { id: string; slug: string; nr: number; label: string; workshop_id: string };
// satt_av er med vilje ikke i typen: feltet skal ikke kunne havne på siden ved
// et uhell senere.
type GRate = { hypothesis_id: string; group_id: string; k: number | null; u: number | null; hensyn: string };

const esc = (s: unknown) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const avsnitt = (s: unknown) => s == null || s === "" ? "" : esc(s).replace(/\r?\n/g, "<br/>");
const tall = (x: number | null) => x == null ? "–" : x.toFixed(1).replace(".", ",");
const pct = (n: number, d: number) => d ? `${Math.round((100 * n) / d)} %` : "–";
const nr = (n: number) => "H-" + String(n ?? 0).padStart(2, "0");
const dato = (iso: string | null) => !iso ? "" : new Date(iso).toLocaleDateString("nb-NO",
  { timeZone: "Europe/Oslo", day: "2-digit", month: "2-digit", year: "numeric" });
const naa = () => new Date().toLocaleString("nb-NO", {
  timeZone: "Europe/Oslo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

/** Samme regnestykke som statsFor() i index.html. Avklart status nullstiller
 *  usikkerheten, men ikke kritikaliteten: en bekreftet kritisk antakelse er
 *  fortsatt kritisk, og det er derfor den er et premiss.
 *
 *  Fra 0021 er `k`/`u` den GJELDENDE plasseringen: endelig_k/u når trakten har
 *  regnet dem ut, ellers individsnittet fra steg 2. Hele siden — seksjoner,
 *  KPI-er og bunker — må lese det samme tallet, ellers sier overskriften én ting
 *  og tabellen under en annen. Individsnittet beholdes som snittK/snittU, slik
 *  at det fortsatt går an å se hva rommet mente før gruppene rørte det. */
function stats(h: Hyp, rates: Rate[]) {
  const ks: number[] = [], us: number[] = [];
  // 0 er «vet ikke»: et eksplisitt svar om manglende grunnlag. Det holdes utenfor
  // snittet, men telles, fordi mange «vet ikke» er et funn i seg selv.
  let vetIkke = 0;
  for (const r of rates) {
    if (r.hypothesis_id !== h.id) continue;
    if (r.k != null && r.k >= 1) ks.push(r.k);
    if (r.u != null && r.u >= 1) us.push(r.u);
    if (r.k === 0 || r.u === 0) vetIkke++;
  }
  const snitt = (a: number[]) => a.length ? a.reduce((s, x) => s + x, 0) / a.length : null;
  const delt = (a: number[]) => {
    if (a.length < MIN_STEMMER) return false;
    const lav = a.filter((x) => x <= MIDT).length / a.length;
    return Math.min(lav, 1 - lav) >= ANDEL && (Math.max(...a) - Math.min(...a)) >= SPRIK;
  };
  const avklart = h.status === "bekreftet" || h.status === "avkreftet";
  const snittK = snitt(ks), snittURaa = snitt(us);
  const snittU = avklart && snittURaa != null ? 1 : snittURaa;

  const fraTrakten = h.endelig_k != null || h.endelig_u != null;
  const k = h.endelig_k ?? snittK;
  const uRaa = h.endelig_u ?? snittURaa;
  // Overstyringen gjelder også det endelige tallet: trakten vet ikke at
  // hypotesen er avklart i ettertid, men siden gjør det.
  const u = avklart && uRaa != null ? 1 : uRaa;
  return {
    k, u, uRaa, snittK, snittU, snittURaa, fraTrakten,
    avklart, n: Math.min(ks.length, us.length),
    vetIkke,
    ingenVet: (ks.length === 0 || us.length === 0) && vetIkke > 0,
    uenig: delt(ks) || delt(us),
    forst: k != null && u != null && k > MIDT && u > MIDT,
  };
}
type Rad = Hyp & ReturnType<typeof stats> & {
  levNr: number; levLabel: string; levCelle: string;
};

const UTEN = "Uten leveranse";
// Hypoteser uten leveranse skal sist, uansett hvor høyt leveransene nummereres.
const SIST = 1e6;

/** Leveransen er det styringsgruppen beslutter på, så den vises med label og
 *  ikke med slug. Den sekundære står i parentes: den sier noe om hvor funnet
 *  også får konsekvenser, men den skal ikke konkurrere med den primære. */
function medLeveranse(r: Hyp & ReturnType<typeof stats>, levs: Map<string, Lev>): Rad {
  const p = r.leveranse ? levs.get(r.leveranse) : undefined;
  const s = r.leveranse_2 ? levs.get(r.leveranse_2) : undefined;
  const label = p?.label ?? (r.leveranse ?? "");
  return {
    ...r,
    levNr: p ? p.nr : SIST,
    levLabel: label || UTEN,
    levCelle: label
      ? esc(label) + (s ? ` <em>(og ${esc(s.label)})</em>` : "")
      : "",
  };
}

// ---------------------------------------------------------------- tabeller
type Kol = [string, (r: Rad) => string];
const K: Record<string, Kol> = {
  krit:   ["Vi vet det når", (r) => avsnitt(r.kriterium)],
  eier:   ["Eier", (r) => r.eier ? esc(r.eier) : "<strong>mangler</strong>"],
  frist:  ["Frist", (r) => r.frist ? esc(dato(r.frist)) : "<strong>mangler</strong>"],
  kr:     ["Kritisk", (r) => tall(r.k)],
  us:     ["Usikker", (r) => tall(r.u)],
  // Ett felt for begge målene på uenighet, fordi de aldri er aktuelle samtidig:
  // gruppespriket finnes bare for hypotesene som gikk gjennom gruppearbeidet, og
  // for dem er det målet som gjelder. Står de i hver sin kolonne, leses en tom
  // celle som «enighet» i stedet for «ikke målt her».
  delt:   ["Delt om", (r) => r.gruppesprik ? "<strong>Gruppene er delt</strong>"
            : r.uenig ? "Rommet er delt" : ""],
  plenum: ["Plenum", (r) => !r.plenum_utfall ? ""
            : `<strong>${esc(PLENUM[r.plenum_utfall] ?? r.plenum_utfall)}</strong>` +
              (r.plenum_notat ? `<br/>${avsnitt(r.plenum_notat)}` : "")],
  vet:    ["Vet ikke", (r) => r.vetIkke ? String(r.vetIkke) + (r.ingenVet ? " (ingen kan svare)" : "") : ""],
  belegg: ["Belegg", (r) => r.avklart ? (avsnitt(r.status_notat) || "<strong>mangler</strong>") : "–"],
};

function tabell(rader: Rad[], kol: Kol[]) {
  const hode = ["Nr", "Leveranse", "Vi tror at", ...kol.map((c) => c[0]), "Kilde"];
  const rad = (r: Rad) => `<tr><td>${esc(nr(r.nr))}</td><td>${r.levCelle}</td>` +
    `<td>${avsnitt(r.tekst)}</td>${kol.map((c) => `<td>${c[1](r)}</td>`).join("")}` +
    `<td>${avsnitt(r.kilde)}</td></tr>`;
  return `<table><tbody><tr>${hode.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>` +
    rader.map(rad).join("") + `</tbody></table>`;
}
const seksjon = (tittel: string, ingress: string, rader: Rad[], kol: Kol[], tom: string) =>
  `<h2>${esc(tittel)}</h2><p>${esc(ingress)}</p>` +
  (rader.length ? tabell(rader, kol) : `<p><em>${esc(tom)}</em></p>`);

// ---------------------------------------------------------------- KPI-fliser
type Kpi = { label: string; verdi: string; sub: string; niva?: "Green" | "Yellow" | "Red" | "Grey"; status?: string };
function flis(k: Kpi) {
  const merke = k.niva
    ? `<p><ac:structured-macro ac:name="status"><ac:parameter ac:name="colour">${k.niva}</ac:parameter>` +
      `<ac:parameter ac:name="title">${esc(k.status)}</ac:parameter></ac:structured-macro></p>` : "";
  return `<ac:layout-cell><ac:structured-macro ac:name="panel"><ac:parameter ac:name="borderStyle">solid</ac:parameter>` +
    `<ac:rich-text-body><p><strong>${esc(k.label)}</strong></p><h1>${esc(k.verdi)}</h1><p>${esc(k.sub)}</p>${merke}` +
    `</ac:rich-text-body></ac:structured-macro></ac:layout-cell>`;
}

function kpier(rader: Rad[], deltakere: number) {
  const vurdert = rader.filter((r) => r.n > 0).length;
  const avklares = rader.filter((r) => r.forst);
  const mangler = avklares.filter((r) => !r.eier || !r.frist).length;
  const avklart = rader.filter((r) => r.avklart);
  const utenBelegg = avklart.filter((r) => !r.status_notat).length;
  const uenige = rader.filter((r) => r.uenig).length;
  const sprikende = rader.filter((r) => r.gruppesprik).length;
  const ubehandlet = rader.filter((r) => r.gruppesprik && !r.plenum_utfall).length;

  const rad1: Kpi[] = [
    { label: "Hypoteser", verdi: String(rader.length), sub: `${vurdert} er vurdert av minst én` },
    { label: "Må avklares", verdi: String(avklares.length),
      sub: "Kritiske og usikre — blokkerer anbefalingen" },
    { label: "Avklart", verdi: String(avklart.length),
      sub: `${avklart.filter((r) => r.status === "bekreftet").length} bekreftet, ` +
           `${avklart.filter((r) => r.status === "avkreftet").length} avkreftet` },
  ];
  const rad2: Kpi[] = [
    { label: "Mangler eier eller frist", verdi: String(mangler),
      sub: `av ${avklares.length} i «Må avklares»`,
      ...(avklares.length === 0 ? { niva: "Grey" as const, status: "Ingen ennå" }
        : mangler === 0 ? { niva: "Green" as const, status: "Komplett" }
        : { niva: "Red" as const, status: "Ikke beslutningsklart" }) },
    { label: "Avklart uten belegg", verdi: String(utenBelegg),
      sub: avklart.length ? `av ${avklart.length} avklarte` : "Ingen avklarte ennå",
      ...(avklart.length === 0 ? { niva: "Grey" as const, status: "Ingen ennå" }
        : utenBelegg === 0 ? { niva: "Green" as const, status: "Sporbart" }
        : { niva: "Yellow" as const, status: "Mangler kilde" }) },
    // Gruppespriket er det som faktisk står på plenumsagendaen, så det skal fram
    // foran individuenigheten så snart gruppene har levert. Før det finnes det
    // ikke noe gruppesprik å vise, og da er individmålet det eneste vi har.
    sprikende
      ? { label: "Gruppene er delt om", verdi: String(sprikende),
          sub: ubehandlet ? `${ubehandlet} er ikke kvittert ut i plenum` : "Alle er kvittert ut i plenum",
          ...(ubehandlet === 0 ? { niva: "Green" as const, status: "Behandlet" }
            : { niva: "Yellow" as const, status: "Står igjen" }) }
      : { label: "Det er uenighet om", verdi: String(uenige),
          sub: `${deltakere} ${deltakere === 1 ? "deltaker har" : "deltakere har"} vurdert` },
  ];
  const del = (ks: Kpi[]) => `<ac:layout-section ac:type="three_equal">${ks.map(flis).join("")}</ac:layout-section>`;
  return del(rad1) + del(rad2);
}

// ---------------------------------------------------------------- siden
function byggSide(hyps: Hyp[], rates: Rate[], levs: Lev[],
                  grupper: Grp[], gRates: GRate[], ubehandlet: number | null) {
  const lev = new Map(levs.map((l) => [l.slug, l]));
  const rader: Rad[] = hyps
    .map((h) => medLeveranse({ ...h, ...stats(h, rates) }, lev))
    .sort((a, b) => a.nr - b.nr);
  const deltakere = new Set(rates.filter((r) => r.k != null || r.u != null).map((r) => r.participant_id)).size;

  // samme inndeling og rekkefølge som markdown-eksporten: hver hypotese havner
  // i nøyaktig én seksjon, og «velg» tømmer puljen etter hvert
  const brukt = new Set<string>();
  const velg = (f: (r: Rad) => boolean) =>
    rader.filter((r) => !brukt.has(r.id) && f(r)).map((r) => { brukt.add(r.id); return r; });

  const avkreftet = velg((r) => r.status === "avkreftet");
  // Eskalert velges før «må avklares»: spørsmålet går videre som et spørsmål og
  // ikke som en oppgave, og en frist på det ville vært feil beskjed.
  const eskalert  = velg((r) => r.plenum_utfall === "eskalert");
  const avklares  = velg((r) => r.forst);
  const grunnlag  = velg((r) => r.k != null && r.u != null && r.k > MIDT && r.u <= MIDT);
  const akseptert = velg((r) => r.k != null && r.u != null && r.k <= MIDT && r.u > MIDT);
  const utenfor   = velg((r) => r.k != null && r.u != null);
  // Må velges før «uvurdert», ellers havner de der under en feil overskrift:
  // disse ER vurdert, rommet hadde bare ikke grunnlag til å svare.
  const ingenVet  = velg((r) => r.ingenVet);
  const uvurdert  = velg(() => true);

  const fraTrakten = rader.some((r) => r.fraTrakten);
  const info = `<ac:structured-macro ac:name="info"><ac:rich-text-body><p>` +
    `Denne siden oppdateres automatisk fra hypoteseregisteret. Endringer gjort for hånd blir ` +
    `overskrevet. Skalaen er 1–10 på begge akser, og grensen mellom feltene går ved ` +
    `${String(MIDT).replace(".", ",")}. Sist oppdatert ${esc(naa())}.` +
    `</p></ac:rich-text-body></ac:structured-macro>`;

  // Merknaden står ØVERST og ikke i en fotnote: poenget er at lista er ærlig om
  // sin egen tilstand, og en leser som ser bunkene før forbeholdet har allerede
  // lest dem som ferdige.
  const merknad = ubehandlet
    ? `<ac:structured-macro ac:name="warning"><ac:rich-text-body><p>` +
      `<strong>Oppgavelista er produsert uten at ${esc(ubehandlet)} ` +
      `${ubehandlet === 1 ? "sak er" : "saker er"} behandlet.</strong> Plenum rakk ikke ` +
      `gjennom hele agendaen. De sakene står fortsatt med gruppenes sprik og uten ` +
      `kvittering, og plasseringen deres er beregnet, ikke besluttet.` +
      `</p></ac:rich-text-body></ac:structured-macro>`
    : "";

  const innhold = [
    merknad,
    avkreftet.length ? seksjon("Avkreftet – dette holdt ikke",
      "Testet og ikke bekreftet. Påvirker anbefalingen direkte.",
      avkreftet, [K.krit, K.belegg, K.eier, K.kr, K.us], "") : "",
    eskalert.length ? seksjon("Eskalert til styringsgruppen",
      "Plenum løste det ikke, og det skal heller ikke løses her. Går videre som et spørsmål, ikke som en oppgave.",
      eskalert, [K.krit, K.plenum, K.kr, K.us, K.delt], "") : "",
    seksjon("Må leveres – avklares før anbefaling",
      "Kritiske og usikre. Hver linje trenger eier og frist for å være en oppgave.",
      avklares, [K.krit, K.eier, K.frist, K.kr, K.us, K.delt, K.plenum, K.vet], "Ingen ennå."),
    // Premissene er kategorien tredelingen må/bør/skal-ikke mangler, og den mest
    // verdifulle for styringsgruppen. Den har derfor sin egen bolk og presses
    // ikke inn i «skal ikke leveres» — et premiss er et svar, ikke en rest.
    seksjon("Premiss – dette legger vi til grunn",
      "Kritiske, men tilstrekkelig avklart. Skrives ned, utredes ikke. Styringsgruppen kan bestride dem.",
      grunnlag, [K.krit, K.belegg, K.eier, K.kr, K.us, K.delt, K.plenum], "Ingen ennå."),
    seksjon("Bør – akseptert usikkerhet",
      "Vi vet lite, og velger bevisst å ikke bruke forprosjektet på det.",
      akseptert, [K.krit, K.eier, K.kr, K.us, K.delt], "Ingen ennå."),
    seksjon("Skal ikke – utenfor",
      "Verken kritisk eller usikkert. Nevnes ikke i anbefalingen.",
      utenfor, [K.krit, K.kr, K.us], "Ingen."),
    ingenVet.length ? seksjon("Ingen kan svare",
      "Alle som svarte, svarte «vet ikke» på minst én akse. Kunnskapen finnes ikke i gruppen og må hentes utenfra. En frist hjelper ikke når ingen vet hvor svaret finnes.",
      ingenVet, [K.krit, K.eier, K.frist, K.vet], "") : "",
    uvurdert.length ? seksjon("Ikke vurdert ennå",
      "Mangler vurdering på minst én akse og er derfor ikke plassert.",
      uvurdert, [K.krit, K.eier, K.frist], "") : "",
    gruppeTabell(rader, grupper, gRates),
    alleTabell(rader, levs, fraTrakten),
  ].filter(Boolean).join("\n");

  const enkelt = (s: string) => `<ac:layout-section ac:type="single"><ac:layout-cell>${s}</ac:layout-cell></ac:layout-section>`;
  return { info: enkelt(info), innhold: kpier(rader, deltakere) + enkelt(innhold) };
}

/** Gruppenes forslag fra steg 3, én rad per gruppe. Et gruppeforslag er ikke en
 *  enkeltstemme — det er fire til fem personer som ble enige om noe de kan leve
 *  med — så det kan vises med gruppenavn. Hvem som førte det i pennen vises
 *  ikke: forslaget er gruppas, ikke lederens. */
function gruppeTabell(rader: Rad[], grupper: Grp[], gRates: GRate[]) {
  if (!gRates.length) return "";
  const navn = new Map(grupper.map((g) => [g.id, g]));
  const perHyp = new Map<string, GRate[]>();
  for (const gr of gRates) {
    if (!perHyp.has(gr.hypothesis_id)) perHyp.set(gr.hypothesis_id, []);
    perHyp.get(gr.hypothesis_id)!.push(gr);
  }

  const hode = ["Nr", "Vi tror at", "Gruppe", "Kritisk", "Usikker",
    "Hensyn forslaget tar", "Gjeldende"];
  const rows: string[] = [];
  for (const r of rader) {
    const g = (perHyp.get(r.id) ?? []).sort((a, b) =>
      (navn.get(a.group_id)?.nr ?? 0) - (navn.get(b.group_id)?.nr ?? 0));
    g.forEach((gr, i) => {
      // Hypotesetekst og det endelige tallet står bare på første rad i bunten.
      // Gjentatt på hver linje ville de lest som fire ulike hypoteser.
      const forst = i === 0;
      rows.push(`<tr>` +
        `<td>${forst ? esc(nr(r.nr)) : ""}</td>` +
        `<td>${forst ? avsnitt(r.tekst) : ""}</td>` +
        `<td>${esc(navn.get(gr.group_id)?.label ?? "Ukjent gruppe")}</td>` +
        // 0 er «vet ikke» også her, og skal ikke se ut som en lav vurdering.
        `<td>${gr.k ? tall(gr.k) : "vet ikke"}</td>` +
        `<td>${gr.u ? tall(gr.u) : "vet ikke"}</td>` +
        `<td>${avsnitt(gr.hensyn)}</td>` +
        `<td>${forst ? `${tall(r.k)} / ${tall(r.u)}` +
          (r.gruppesprik ? " <strong>(gruppene er delt)</strong>" : "") : ""}</td></tr>`);
    });
  }
  if (!rows.length) return "";

  return `<h2>Gruppenes forslag</h2><p>Utvalget gruppene rakk gjennom i steg 3. ` +
    `Oppgaven var ikke å bli enige, men å lage et forslag alle i gruppen kan leve med ` +
    `— derfor står hensynene ved siden av tallet. «Gjeldende» er snittet av ` +
    `gruppeforslagene, eller det plenum justerte det til. Hvem som førte forslaget ` +
    `i pennen publiseres ikke.</p>` +
    `<table><tbody><tr>${hode.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>` +
    rows.join("") + `</tbody></table>`;
}

/** Hele registeret, gruppert etter leveranse. Grupperingen er poenget: en
 *  leveranse uten evidens skal være synlig som et hull, ikke drukne i en lang
 *  liste. Individuelle vurderinger er ikke med — bare snitt, antall og
 *  uenighetsflagget. */
function alleTabell(rader: Rad[], levs: Lev[], fraTrakten: boolean) {
  const hode = ["Nr", "Vi tror at", "Vi vet det når", "Status", "Belegg", "Avklart",
    "Eier", "Frist", "Kritisk", "Usikker", "Individsnitt K", "Individsnitt U",
    "Usikker vurdert", "Vurderinger", "Vet ikke", "Delt om", "Plenum", "Kilde"];
  const rad = (r: Rad) => `<tr><td>${esc(nr(r.nr))}</td>` +
    `<td>${avsnitt(r.tekst)}</td><td>${avsnitt(r.kriterium)}</td>` +
    `<td>${esc(STATUS[r.status] ?? r.status)}</td><td>${avsnitt(r.status_notat)}</td>` +
    `<td>${esc(r.status_endret ? dato(r.status_endret) + (r.status_av ? " / " + r.status_av : "") : "")}</td>` +
    `<td>${esc(r.eier)}</td><td>${esc(dato(r.frist))}</td>` +
    `<td>${tall(r.k)}</td><td>${tall(r.u)}</td>` +
    `<td>${tall(r.snittK)}</td><td>${tall(r.snittU)}</td><td>${tall(r.snittURaa)}</td>` +
    `<td>${r.n}</td><td>${r.vetIkke || ""}</td><td>${K.delt[1](r)}</td>` +
    `<td>${K.plenum[1](r)}</td>` +
    `<td>${avsnitt(r.kilde)}</td></tr>`;

  const grupper = new Map<string, { nr: number; label: string; rader: Rad[] }>();
  // Alle leveransene legges inn FØR hypotesene fordeles, slik at de tomme blir
  // stående. En leveranse uten en eneste hypotese er det kraftigste signalet
  // siden kan gi — hoppes den over, ser rapporten komplett ut nettopp der
  // grunnlaget mangler helt.
  for (const l of levs) grupper.set(`${l.nr}|${l.label}`, { nr: l.nr, label: l.label, rader: [] });
  for (const r of rader) {
    // Nøkkelen tar med labelen: en hypotese kan peke på en leveranse som er
    // slettet fra lista, og den skal ikke smelte sammen med «Uten leveranse».
    const n = `${r.levNr}|${r.levLabel}`;
    const g = grupper.get(n) ?? { nr: r.levNr, label: r.levLabel, rader: [] };
    g.rader.push(r);
    grupper.set(n, g);
  }
  const deler = [...grupper.values()]
    .sort((a, b) => a.nr - b.nr || a.label.localeCompare(b.label, "nb"))
    .map((g) =>
      `<h3>${esc(g.label)}</h3>` +
      (g.rader.length
        ? `<table><tbody><tr>${hode.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>` +
          g.rader.map(rad).join("") + `</tbody></table>`
        : `<p><strong>Ingen hypoteser er koblet til denne leveransen.</strong> ` +
          `Det betyr at ingenting i registeret underbygger den ennå.</p>`));

  return `<h2>Alle hypoteser</h2><p>Hele registeret samlet, gruppert etter leveransen ` +
    `hypotesen hører til. «Kritisk» og «Usikker» er den gjeldende plasseringen: ` +
    (fraTrakten
      ? `det trakten endte på, altså snittet av gruppeforslagene for hypotesene som gikk ` +
        `til gruppearbeid, eller det plenum justerte det til. `
      : `individsnittet, fordi trakten ennå ikke har regnet ut noe endelig tall. `) +
    `«Individsnitt» er hva den enkelte deltakeren stemte i steg 2, og står ved siden av ` +
    `slik at det går an å se hva gruppene faktisk flyttet på. ` +
    `«Usikker vurdert» er individsnittet før avklart status overstyrer det til 1. ` +
    `Individuelle vurderinger publiseres ikke.</p>` + deler.join("");
}

// ---------------------------------------------------------------- Confluence
async function confluence(sti: string, init: RequestInit = {}) {
  const base = Deno.env.get("CONFLUENCE_BASE_URL")!.replace(/\/+$/, "");
  const auth = btoa(`${Deno.env.get("CONFLUENCE_EMAIL")}:${Deno.env.get("CONFLUENCE_API_TOKEN")}`);
  return await fetch(`${base}/wiki/api/v2${sti}`, {
    ...init,
    headers: { Authorization: `Basic ${auth}`, Accept: "application/json", "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

Deno.serve(async (req) => {
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: hemmelighet, error: he } = await sb.rpc("confluence_sync_secret");
  if (he || !hemmelighet || !(await likt(req.headers.get("x-sync-secret") ?? "", hemmelighet))) {
    return new Response("forbidden", { status: 403 });
  }

  const { data: hyps, error: e1 } = await sb.from("hypotheses")
    .select("id, nr, tekst, kriterium, leveranse, leveranse_2, status, kilde, eier, frist, " +
            "status_notat, status_endret, status_av, created_at, workshop_id, " +
            "i_gruppearbeid, endelig_k, endelig_u, gruppesprik, plenum_utfall, plenum_notat")
    .is("deleted_at", null)
    // Kladd er personlig og har ikke engang fått nummer ennå. Den hører ikke
    // hjemme på en side resten av prosjektet leser.
    .eq("publisert", true);
  if (e1) return Response.json({ ok: false, steg: "les hypoteser", feil: e1.message }, { status: 500 });

  const { data: rates, error: e2 } = await sb.from("ratings").select("hypothesis_id, participant_id, k, u");
  if (e2) return Response.json({ ok: false, steg: "les vurderinger", feil: e2.message }, { status: 500 });

  const { data: levs, error: e3 } = await sb.from("deliverables").select("slug, nr, label").order("nr");
  if (e3) return Response.json({ ok: false, steg: "les leveranser", feil: e3.message }, { status: 500 });

  // group_ratings.satt_av hentes IKKE ut. Gruppas forslag er gruppas, ikke
  // lederens, og et felt som aldri forlater databasen kan heller ikke lekke inn
  // på siden ved en senere endring.
  //
  // Feil her er ikke fatalt: finnes ikke tabellene ennå, er siden den samme som
  // før gruppearbeidet. En tom gruppebolk og en manglende tabell er samme bilde
  // for leseren, og en workshop skal ikke stoppe fordi Confluence-siden mangler
  // en seksjon.
  const { data: grps } = await sb.from("groups").select("id, slug, nr, label, workshop_id").order("nr");
  const { data: gRates } = await sb.from("group_ratings").select("hypothesis_id, group_id, k, u, hensyn");

  // Navnene brukes bare til å vise hvem som avklarte en status. Hvem som la
  // inn hypotesen publiseres ikke: registeret vedlikeholdes fra backend, og
  // forfatteren er verken relevant eller noe leserne skal forholde seg til.
  const { data: deltakere } = await sb.from("participants").select("id, name");
  const navn = new Map((deltakere ?? []).map((p: { id: string; name: string }) => [p.id, p.name]));

  const levende = new Set((hyps ?? []).map((h: { id: string }) => h.id));
  const rader = (hyps ?? []).map((h: Record<string, unknown>) => ({
    ...h,
    status_av: h.status_av ? (navn.get(String(h.status_av)) ?? null) : null,
  })) as Hyp[];

  // Merknaden om ubehandlede saker hentes fra workshopen hypotesene tilhører.
  // Registeret har i praksis én, men å lese den via hypotesene framfor å ta den
  // første i tabellen gjør at en gammel testworkshop ikke kan sette et forbehold
  // på en side som ikke gjelder den.
  const wsId = rader[0]?.workshop_id;
  const { data: ws } = await sb.from("workshops").select("id, oppgaver_apnet_ubehandlet");
  const ubehandlet = (ws ?? []).find((w: { id: string }) => w.id === wsId)
    ?.oppgaver_apnet_ubehandlet ?? null;

  const side = byggSide(
    rader,
    (rates ?? []).filter((r: Rate) => levende.has(r.hypothesis_id)) as Rate[],
    (levs ?? []) as Lev[],
    (grps ?? []) as Grp[],
    ((gRates ?? []) as GRate[]).filter((g) => levende.has(g.hypothesis_id)),
    ubehandlet,
  );
  const html = `<ac:layout>${side.info}${side.innhold}</ac:layout>`;

  // ?dry=1 gir den ferdige siden uten å røre Confluence (til testing)
  if (new URL(req.url).searchParams.get("dry")) {
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  }

  const pageId = Deno.env.get("CONFLUENCE_PAGE_ID");
  if (!pageId || !Deno.env.get("CONFLUENCE_BASE_URL") || !Deno.env.get("CONFLUENCE_EMAIL") || !Deno.env.get("CONFLUENCE_API_TOKEN")) {
    return Response.json({ ok: false, hoppet_over: "confluence er ikke satt opp", hypoteser: rader.length }, { status: 200 });
  }

  // Skriv bare når innholdet uten tidsstempelet er endret. Alt som skal kunne
  // utløse en oppdatering må ligge i side.innhold — et felt som bare havner i
  // side.info, blir usynlig for summen og dermed aldri skrevet.
  const sum = await crypto.subtle.digest("SHA-256", enc.encode(side.innhold));
  const hash = [...new Uint8Array(sum)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const { data: endret, error: ce } = await sb.rpc("confluence_sync_changed", { new_hash: hash });
  if (ce) return Response.json({ ok: false, steg: "endringssjekk", feil: ce.message }, { status: 500 });
  if (!endret) return Response.json({ ok: true, uendret: true }, { status: 200 });

  // ved feil glemmes den lagrede summen, så neste kjøring prøver på nytt
  const feilet = async (body: Record<string, unknown>) => {
    await sb.rpc("confluence_sync_changed", { new_hash: `failed-${Date.now()}` });
    return Response.json({ ok: false, ...body }, { status: 502 });
  };

  // to endringer samtidig kan kollidere på sideversjonen: les på nytt og prøv én gang til
  for (let forsok = 0; forsok < 2; forsok++) {
    const g = await confluence(`/pages/${pageId}`);
    if (!g.ok) return feilet({ steg: "hent side", status: g.status });
    const naavaerende = await g.json();
    const u = await confluence(`/pages/${pageId}`, {
      method: "PUT",
      body: JSON.stringify({
        id: pageId, status: "current", title: naavaerende.title,
        body: { representation: "storage", value: html },
        version: { number: naavaerende.version.number + 1, message: `Automatisk oppdatert (${rader.length} hypoteser)` },
      }),
    });
    if (u.ok) return Response.json({ ok: true, hypoteser: rader.length, versjon: naavaerende.version.number + 1 }, { status: 200 });
    if (u.status !== 409) return feilet({ steg: "oppdater side", status: u.status, body: (await u.text()).slice(0, 300) });
  }
  return feilet({ steg: "oppdater side", status: 409 });
});
