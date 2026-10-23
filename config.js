// Offentlig klientkonfigurasjon. Nøkkelen er en publishable key og er ment å ligge i
// nettleseren: tabellene er stengt med RLS, og all tilgang krever en innlogget sesjon.
window.NORDLYS_CONFIG = {
  supabaseUrl: "https://ryzeahdqxtclliyhdlki.supabase.co",
  supabaseKey: "sb_publishable_M5J3j-v4x0pNokomjnnw7g_laM9zTQ1",
  pollMs: 4000
};

// Åpnes fila direkte med file://, peker den likevel hit — mot PRODUKSJON. Da
// sendes det ekte innloggingskoder til ekte innbokser, og feilene ser ut som
// feil i koden i stedet for feil miljø. Det kostet flere runder å oppdage.
//
// På GitHub Pages er protokollen https, så dette slår aldri til for deltakerne.
if (location.protocol === "file:") {
  addEventListener("DOMContentLoaded", () => {
    const b = document.createElement("div");
    b.innerHTML = "<strong>Du har åpnet fila direkte.</strong> Da kjører appen mot "
      + "<strong>produksjonsdatabasen</strong>, og innlogging sender ekte e-post. "
      + "Start en server i stedet: <code>python3 -m http.server 8777</code>";
    b.style.cssText = "position:fixed;left:0;right:0;top:0;z-index:9999;background:#8a1c1c;"
      + "color:#fff;font:14px/1.5 system-ui,sans-serif;padding:12px 16px;text-align:center";
    document.body.prepend(b);
  });
}
