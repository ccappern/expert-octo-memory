-- 0022: workshopavstemning uten innlogging.
--
-- Bakgrunn: innloggingen med engangskode på e-post er for mye friksjon når 21
-- personer fra sju virksomheter skal i gang på ti minutter. Sju bedriftsgatewayer
-- betyr sju spamfiltre, og Supabase sin innebygde e-posttjeneste er dessuten
-- ratebegrenset. Risikoen for at halve rommet står utenfor klokka 14.35 er reell,
-- og prisen er hele økten.
--
-- Derfor: identiteten er et navn deltakeren velger selv. Den er PÅSTÅTT, ikke
-- verifisert, og det er med vilje. Trusselbildet er 21 personer i samme rom som
-- ser hverandre; det finnes ingen angriper å forsvare seg mot, og en sperre som
-- koster mer enn den beskytter er ingen sperre.
--
-- Tabellene står helt for seg selv: ingen fremmednøkler til hypotheses eller
-- participants, bare hypotesenummeret som tall. Det gjør at denne migrasjonen
-- ikke kan ødelegge noe som allerede virker, og at den kan droppes i sin helhet
-- etter workshopen uten å etterlate seg hull.

create table if not exists public.ws_prioritet (
  navn text not null,
  nr int not null,
  -- maa = må avklares før go/no-go, bor = bør avklares dersom mulig,
  -- vent = kan vente til neste fase. Tredelingen er fasilitators, ikke vår.
  prioritet text not null check (prioritet in ('maa','bor','vent')),
  oppdatert timestamptz not null default now(),
  primary key (navn, nr)
);

create table if not exists public.ws_gruppe (
  navn text not null,
  nr int not null,
  god_nok boolean,
  forenkling text not null default '',
  validering text not null default '',
  oppdatert timestamptz not null default now(),
  primary key (navn, nr)
);

-- RLS på, og ingen policy: da er tabellene stengt for direkte lesing og skriving
-- med den publiserbare nøkkelen. All tilgang går gjennom funksjonene under, som
-- er security definer og dermed omgår RLS kontrollert.
alter table public.ws_prioritet enable row level security;
alter table public.ws_gruppe    enable row level security;

-- ---------- skriving ----------

drop function if exists public.ws_sett_prioritet(text, int, text);
create function public.ws_sett_prioritet(p_navn text, p_nr int, p_prioritet text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  -- Navnet trimmes og må finnes. Uten det ville et tomt felt samlet alle
  -- som glemte å velge navn i én og samme «deltaker».
  if coalesce(btrim(p_navn), '') = '' then
    raise exception 'Mangler navn' using errcode = '23514';
  end if;
  if p_prioritet not in ('maa','bor','vent') then
    raise exception 'Ukjent prioritet: %', p_prioritet using errcode = '23514';
  end if;

  insert into public.ws_prioritet (navn, nr, prioritet)
  values (btrim(p_navn), p_nr, p_prioritet)
  on conflict (navn, nr) do update
    set prioritet = excluded.prioritet, oppdatert = now();
end $$;

drop function if exists public.ws_sett_gruppe(text, int, boolean, text, text);
create function public.ws_sett_gruppe(
  p_navn text, p_nr int, p_god_nok boolean,
  p_forenkling text default '', p_validering text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if coalesce(btrim(p_navn), '') = '' then
    raise exception 'Mangler navn' using errcode = '23514';
  end if;

  insert into public.ws_gruppe (navn, nr, god_nok, forenkling, validering)
  values (btrim(p_navn), p_nr, p_god_nok,
          left(coalesce(p_forenkling, ''), 2000), left(coalesce(p_validering, ''), 2000))
  on conflict (navn, nr) do update
    set god_nok    = excluded.god_nok,
        forenkling = excluded.forenkling,
        validering = excluded.validering,
        oppdatert  = now();
end $$;

-- ---------- lesing ----------

-- Tellingene gjøres HER og ikke i klienten, av samme grunn som deltakertallene
-- ellers i registeret: klienten kjenner bare sine egne rader og ville alltid
-- rapportert én deltaker.
--
-- Merk at dette er en ren opptelling uten ankringssperre. Det er riktig her:
-- resultatbildet er selve poenget med steg 3 — rommet skal SE hvilke som peker
-- seg ut for å kunne skjære ned til 6–10. Sperren i hovedverktøyet gjelder mens
-- folk stemmer individuelt, og det steget er over når dette bildet vises.
drop function if exists public.ws_status();
create function public.ws_status()
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'deltakere', (select count(distinct navn) from public.ws_prioritet),
    'prioritet', coalesce((
      select json_agg(json_build_object(
        'nr', t.nr, 'maa', t.maa, 'bor', t.bor, 'vent', t.vent)
        order by t.maa desc, t.nr)
      from (
        select nr,
               count(*) filter (where prioritet = 'maa')  as maa,
               count(*) filter (where prioritet = 'bor')  as bor,
               count(*) filter (where prioritet = 'vent') as vent
        from public.ws_prioritet group by nr
      ) t), '[]'::json),
    -- Gruppesvarene sendes med navn: de er en arbeidsnotat fra fire grupper
    -- som uansett presenterer dem muntlig i steg 5, ikke en hemmelig stemme.
    'gruppe', coalesce((
      select json_agg(json_build_object(
        'nr', nr, 'navn', navn, 'god_nok', god_nok,
        'forenkling', forenkling, 'validering', validering) order by nr, navn)
      from public.ws_gruppe), '[]'::json)
  );
$$;

-- anon og ikke bare authenticated: det er hele poenget. Deltakerne har ingen
-- sesjon, bare den publiserbare nøkkelen som allerede ligger i config.js.
grant execute on function public.ws_sett_prioritet(text, int, text) to anon, authenticated;
grant execute on function public.ws_sett_gruppe(text, int, boolean, text, text) to anon, authenticated;
grant execute on function public.ws_status() to anon, authenticated;

notify pgrst, 'reload schema';
