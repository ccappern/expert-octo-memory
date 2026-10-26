-- 0025: oppsummeringstabellen som fylles ut live.
--
-- Steg 6 er der workshopen faktisk leverer: hypotese, er den kritisk før
-- go/no-go, hvordan valideres den, hvem eier den, hva er neste steg. Uten et
-- sted å skrive det, ender dagen i en muntlig runde og et referat noen skal
-- skrive i morgen — og da er eierskapet borte før det ble satt.
--
-- Én rad per hypotese, og raden er FELLES. I motsetning til ws_prioritet (per
-- person) og ws_gruppe (per gruppe) er dette fasilitators tabell, projisert på
-- storskjerm mens rommet ser på. Da er «siste skriving vinner» riktig: det er
-- én person som fører i pennen, og rommet ser hva som står.

create table if not exists public.ws_oppsum (
  nr int primary key,
  kritisk text not null default '' check (kritisk in ('', 'ja', 'nei')),
  validering text not null default '',
  eier text not null default '',
  neste text not null default '',
  oppdatert timestamptz not null default now()
);

alter table public.ws_oppsum enable row level security;

drop function if exists public.ws_sett_oppsum(text, int, text, text, text, text);
create function public.ws_sett_oppsum(
  p_kode text, p_nr int,
  p_kritisk text default '', p_validering text default '',
  p_eier text default '', p_neste text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
  if coalesce(p_kritisk, '') not in ('', 'ja', 'nei') then
    raise exception 'Ukjent verdi for kritisk: %', p_kritisk using errcode = '23514';
  end if;

  insert into public.ws_oppsum (nr, kritisk, validering, eier, neste)
  values (p_nr, coalesce(p_kritisk, ''),
          left(coalesce(p_validering, ''), 2000),
          left(coalesce(p_eier, ''), 200),
          left(coalesce(p_neste, ''), 2000))
  on conflict (nr) do update
    set kritisk    = excluded.kritisk,
        validering = excluded.validering,
        eier       = excluded.eier,
        neste      = excluded.neste,
        oppdatert  = now();
end $$;

-- ws_status utvides med `oppsum`. Gammel utgave droppes først, slik at
-- PostgREST ikke kan ende opp med å velge en uten det nye feltet.
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
        'kriterium', kriterium) order by navn, lopenr)
      from public.ws_ny), '[]'::json),
    'oppsum', coalesce((
      select json_agg(json_build_object(
        'nr', nr, 'kritisk', kritisk, 'validering', validering,
        'eier', eier, 'neste', neste) order by nr)
      from public.ws_oppsum), '[]'::json)
  ));
end $$;

grant execute on function public.ws_sett_oppsum(text, int, text, text, text, text) to anon, authenticated;
grant execute on function public.ws_status(text) to anon, authenticated;

notify pgrst, 'reload schema';
