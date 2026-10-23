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
// appen heller ikke eksporterer enkeltstemmer.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SKALA = 10;
const MIDT = (1 + SKALA) / 2;          // 5,5 — samme grense som i klienten
const ANDEL = 0.30;
const SPRIK = 4;
const MIN_STEMMER = 3;

const STATUS: Record<string, string> = {
  ny: "Ny", testes: "Testes", bekreftet: "Bekreftet", avkreftet: "Avkreftet",
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
  by: string | null; created_at: string;
};
type Lev = { slug: string; nr: number; label: string };
type Rate = { hypothesis_id: string; participant_id: string; k: number | null; u: number | null };

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
 *  fortsatt kritisk, og det er derfor den er et premiss. */
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
  const k = snitt(ks), uRaa = snitt(us);
  const u = avklart && uRaa != null ? 1 : uRaa;
  return {
    k, u, uRaa, avklart, n: Math.min(ks.length, us.length),
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
  uenig:  ["Uenige", (r) => r.uenig ? "Ja" : ""],
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
    { label: "Det er uenighet om", verdi: String(uenige),
      sub: `${deltakere} ${deltakere === 1 ? "deltaker har" : "deltakere har"} vurdert` },
  ];
  const del = (ks: Kpi[]) => `<ac:layout-section ac:type="three_equal">${ks.map(flis).join("")}</ac:layout-section>`;
  return del(rad1) + del(rad2);
}

// ---------------------------------------------------------------- siden
function byggSide(hyps: Hyp[], rates: Rate[], levs: Lev[]) {
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
  const avklares  = velg((r) => r.forst);
  const grunnlag  = velg((r) => r.k != null && r.u != null && r.k > MIDT && r.u <= MIDT);
  const akseptert = velg((r) => r.k != null && r.u != null && r.k <= MIDT && r.u > MIDT);
  const utenfor   = velg((r) => r.k != null && r.u != null);
  // Må velges før «uvurdert», ellers havner de der under en feil overskrift:
  // disse ER vurdert, rommet hadde bare ikke grunnlag til å svare.
  const ingenVet  = velg((r) => r.ingenVet);
  const uvurdert  = velg(() => true);

  const info = `<ac:structured-macro ac:name="info"><ac:rich-text-body><p>` +
    `Denne siden oppdateres automatisk fra hypoteseregisteret. Endringer gjort for hånd blir ` +
    `overskrevet. Skalaen er 1–10 på begge akser, og grensen mellom feltene går ved ` +
    `${String(MIDT).replace(".", ",")}. Sist oppdatert ${esc(naa())}.` +
    `</p></ac:rich-text-body></ac:structured-macro>`;

  const innhold = [
    avkreftet.length ? seksjon("Avkreftet – dette holdt ikke",
      "Testet og ikke bekreftet. Påvirker anbefalingen direkte.",
      avkreftet, [K.krit, K.belegg, K.eier, K.kr, K.us], "") : "",
    seksjon("Må avklares før anbefaling",
      "Kritiske og usikre. Hver linje trenger eier og frist for å være en oppgave.",
      avklares, [K.krit, K.eier, K.frist, K.kr, K.us, K.uenig, K.vet], "Ingen ennå."),
    seksjon("Dette legger vi til grunn",
      "Kritiske, men tilstrekkelig avklart. Premisser styringsgruppen kan bestride.",
      grunnlag, [K.krit, K.belegg, K.eier, K.kr, K.us, K.uenig], "Ingen ennå."),
    seksjon("Akseptert usikkerhet",
      "Vi vet lite, og velger bevisst å ikke bruke forprosjektet på det.",
      akseptert, [K.krit, K.eier, K.kr, K.us], "Ingen ennå."),
    seksjon("Utenfor",
      "Verken kritisk eller usikkert. Nevnes ikke i anbefalingen.",
      utenfor, [K.krit, K.kr, K.us], "Ingen."),
    ingenVet.length ? seksjon("Ingen kan svare",
      "Alle som svarte, svarte «vet ikke» på minst én akse. Kunnskapen finnes ikke i gruppen og må hentes utenfra.",
      ingenVet, [K.krit, K.eier, K.frist, K.vet], "") : "",
    uvurdert.length ? seksjon("Ikke vurdert ennå",
      "Mangler vurdering på minst én akse og er derfor ikke plassert.",
      uvurdert, [K.krit, K.eier, K.frist], "") : "",
    alleTabell(rader),
  ].filter(Boolean).join("\n");

  const enkelt = (s: string) => `<ac:layout-section ac:type="single"><ac:layout-cell>${s}</ac:layout-cell></ac:layout-section>`;
  return { info: enkelt(info), innhold: kpier(rader, deltakere) + enkelt(innhold) };
}

/** Hele registeret, gruppert etter leveranse. Grupperingen er poenget: en
 *  leveranse uten evidens skal være synlig som et hull, ikke drukne i en lang
 *  liste. Individuelle vurderinger er ikke med — bare snitt, antall og
 *  uenighetsflagget. */
function alleTabell(rader: Rad[]) {
  const hode = ["Nr", "Vi tror at", "Vi vet det når", "Status", "Belegg", "Avklart",
    "Eier", "Frist", "Kritisk", "Usikker", "Usikker vurdert", "Vurderinger", "Vet ikke", "Uenige", "Kilde", "Lagt inn av"];
  const rad = (r: Rad) => `<tr><td>${esc(nr(r.nr))}</td>` +
    `<td>${avsnitt(r.tekst)}</td><td>${avsnitt(r.kriterium)}</td>` +
    `<td>${esc(STATUS[r.status] ?? r.status)}</td><td>${avsnitt(r.status_notat)}</td>` +
    `<td>${esc(r.status_endret ? dato(r.status_endret) + (r.status_av ? " / " + r.status_av : "") : "")}</td>` +
    `<td>${esc(r.eier)}</td><td>${esc(dato(r.frist))}</td>` +
    `<td>${tall(r.k)}</td><td>${tall(r.u)}</td><td>${tall(r.uRaa)}</td>` +
    `<td>${r.n}</td><td>${r.vetIkke || ""}</td><td>${r.uenig ? "Ja" : ""}</td>` +
    `<td>${avsnitt(r.kilde)}</td><td>${esc(r.by ?? "")}</td></tr>`;

  const grupper = new Map<string, { nr: number; label: string; rader: Rad[] }>();
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
    .map((g) => `<h3>${esc(g.label)}</h3>` +
      `<table><tbody><tr>${hode.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>` +
      g.rader.map(rad).join("") + `</tbody></table>`);

  return `<h2>Alle hypoteser</h2><p>Hele registeret samlet, gruppert etter leveransen ` +
    `hypotesen hører til. «Usikker» er overstyrt til 1 for avklarte hypoteser; ` +
    `«Usikker vurdert» er det deltakerne faktisk stemte. Individuelle vurderinger ` +
    `publiseres ikke.</p>` + deler.join("");
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
    .select("id, nr, tekst, kriterium, type, leveranse, leveranse_2, status, kilde, eier, frist, status_notat, status_endret, status_av, created_by, created_at")
    .is("deleted_at", null)
    // Kladd er personlig og har ikke engang fått nummer ennå. Den hører ikke
    // hjemme på en side resten av prosjektet leser.
    .eq("publisert", true);
  if (e1) return Response.json({ ok: false, steg: "les hypoteser", feil: e1.message }, { status: 500 });

  const { data: rates, error: e2 } = await sb.from("ratings").select("hypothesis_id, participant_id, k, u");
  if (e2) return Response.json({ ok: false, steg: "les vurderinger", feil: e2.message }, { status: 500 });

  const { data: levs, error: e3 } = await sb.from("deliverables").select("slug, nr, label").order("nr");
  if (e3) return Response.json({ ok: false, steg: "les leveranser", feil: e3.message }, { status: 500 });

  const { data: deltakere } = await sb.from("participants").select("id, name");
  const navn = new Map((deltakere ?? []).map((p: { id: string; name: string }) => [p.id, p.name]));

  const levende = new Set((hyps ?? []).map((h: { id: string }) => h.id));
  const rader = (hyps ?? []).map((h: Record<string, unknown>) => ({
    ...h,
    by: navn.get(String(h.created_by)) ?? null,
    status_av: h.status_av ? (navn.get(String(h.status_av)) ?? null) : null,
  })) as Hyp[];

  const side = byggSide(rader, (rates ?? []).filter((r: Rate) => levende.has(r.hypothesis_id)) as Rate[], (levs ?? []) as Lev[]);
  const html = `<ac:layout>${side.info}${side.innhold}</ac:layout>`;

  // ?dry=1 gir den ferdige siden uten å røre Confluence (til testing)
  if (new URL(req.url).searchParams.get("dry")) {
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  }

  const pageId = Deno.env.get("CONFLUENCE_PAGE_ID");
  if (!pageId || !Deno.env.get("CONFLUENCE_BASE_URL") || !Deno.env.get("CONFLUENCE_EMAIL") || !Deno.env.get("CONFLUENCE_API_TOKEN")) {
    return Response.json({ ok: false, hoppet_over: "confluence er ikke satt opp", hypoteser: rader.length }, { status: 200 });
  }

  // skriv bare når innholdet uten tidsstempelet er endret
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
