-- 0024: gruppene kan foreslå hypoteser som mangler.
--
-- Gruppearbeidet handlet bare om hypotesene som allerede finnes. Men registeret
-- er kuttet fra 28 til 9, og tre av leveransene har ingen hypoteser i det hele
-- tatt. Spørsmålet «mangler det noe?» er derfor minst like viktig som «er denne
-- god nok?» — og uten et sted å skrive det, forsvinner svaret i en muntlig
-- runde ingen rakk å notere.
--
-- Avsenderen er GRUPPA, som i ws_gruppe. Løpenummeret settes av klienten, så en
-- gruppe kan foreslå flere og rette sine egne uten at vi trenger en id-runde.
-- Primærnøkkelen (navn, lopenr) gjør at samme gruppe som skriver videre
-- oppdaterer sin egen rad i stedet for å lage en ny for hvert tastetrykk.

create table if not exists public.ws_ny (
  navn text not null,
  lopenr int not null,
  tekst text not null default '',
  kriterium text not null default '',
  leveranse text not null default '',
  oppdatert timestamptz not null default now(),
  primary key (navn, lopenr)
);

alter table public.ws_ny enable row level security;

drop function if exists public.ws_sett_ny(text, text, int, text, text, text);
create function public.ws_sett_ny(
  p_kode text, p_navn text, p_lopenr int,
  p_tekst text default '', p_kriterium text default '', p_leveranse text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
  if coalesce(btrim(p_navn), '') = '' then
    raise exception 'Mangler gruppenavn' using errcode = '23514';
  end if;

  -- Tom påstand betyr at forslaget er angret. Da skal raden bort, ikke stå
  -- igjen som et tomt punkt i den felles gjennomgangen.
  if coalesce(btrim(p_tekst), '') = '' then
    delete from public.ws_ny where navn = btrim(p_navn) and lopenr = p_lopenr;
    return;
  end if;

  insert into public.ws_ny (navn, lopenr, tekst, kriterium, leveranse)
  values (btrim(p_navn), p_lopenr,
          left(btrim(p_tekst), 2000),
          left(coalesce(p_kriterium, ''), 2000),
          left(coalesce(p_leveranse, ''), 200))
  on conflict (navn, lopenr) do update
    set tekst     = excluded.tekst,
        kriterium = excluded.kriterium,
        leveranse = excluded.leveranse,
        oppdatert = now();
end $$;

-- ws_status utvides med `nye`. Signaturen er uendret, men funksjonen må
-- gjenskapes i sin helhet — og den gamle droppes først, slik at PostgREST
-- ikke kan ende opp med å velge en utgave uten det nye feltet.
drop function if exists public.ws_status(text);
create function public.ws_status(p_kode text)
returns json language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
  return (select json_build_object(
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
    'gruppe', coalesce((
      select json_agg(json_build_object(
        'nr', nr, 'navn', navn, 'god_nok', god_nok,
        'forenkling', forenkling, 'validering', validering) order by nr, navn)
      from public.ws_gruppe), '[]'::json),
    'nye', coalesce((
      select json_agg(json_build_object(
        'navn', navn, 'lopenr', lopenr, 'tekst', tekst,
        'kriterium', kriterium, 'leveranse', leveranse) order by navn, lopenr)
      from public.ws_ny), '[]'::json)
  ));
end $$;

grant execute on function public.ws_sett_ny(text, text, int, text, text, text) to anon, authenticated;
grant execute on function public.ws_status(text) to anon, authenticated;

notify pgrst, 'reload schema';
