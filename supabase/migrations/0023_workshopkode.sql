-- 0023: workshopkode foran avstemningen.
--
-- 0022 åpnet tre funksjoner for `anon`, fordi innlogging med engangskode var
-- for mye friksjon. Prisen var at hvem som helst med URL-en kunne skrive. Det
-- er ikke et personvernproblem — hypotesene er et forslag som uansett skal
-- presenteres — men det er et integritetsproblem: en avstemning som kan fylles
-- utenfra er ikke en avstemning.
--
-- Koden ligger derfor HER og ikke i klienten. En sperre i en statisk fil på
-- GitHub Pages er ingen sperre: kildekoden er offentlig lesbar, og den som
-- leter finner koden. Sperren i klienten holder tilfeldige ute; denne holder
-- dataene i orden.
--
-- Koden settes med et eget kall etter at migrasjonen er kjørt, og står ikke i
-- repoet. Den deles muntlig i rommet, slik 0011 gjorde før Supabase Auth.

create table if not exists private.ws_kode (
  id boolean primary key default true check (id),
  kode text not null,
  satt timestamptz not null default now()
);

-- Plassholder som ikke kan gjettes og ikke er ment å brukes: settes den ikke,
-- slipper ingen inn, og det er riktig feilretning. En tom eller forutsigbar
-- standardverdi ville åpnet alt i stedet.
insert into private.ws_kode (id, kode)
values (true, encode(extensions.gen_random_bytes(16), 'hex'))
on conflict (id) do nothing;

-- Sammenligningen er enkel med vilje: dette er en workshopkode som deles
-- muntlig, ikke et passord som beskytter noe hemmelig. Trimmet og
-- versalufølsom, fordi den tastes inn av 21 personer under tidspress.
create or replace function private.ws_sjekk(p_kode text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if lower(btrim(coalesce(p_kode, ''))) <> lower((select kode from private.ws_kode where id)) then
    raise exception 'Feil kode' using errcode = '42501';
  end if;
end $$;

-- Fasilitator setter koden. Krever innlogget administrator, så den kan ikke
-- byttes av en deltaker midt i økten.
create or replace function public.ws_sett_kode(p_kode text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.meg_admin();
  if char_length(btrim(coalesce(p_kode, ''))) < 4 then
    raise exception 'Koden må være minst fire tegn' using errcode = '23514';
  end if;
  update private.ws_kode set kode = btrim(p_kode), satt = now() where id;
end $$;

-- ---------- funksjonene fra 0022, nå med kode ----------
-- Signaturene endres, så de gamle utgavene MÅ droppes. Blir de liggende,
-- velger PostgREST feil utgave og sperren er borte uten at noen merker det.

drop function if exists public.ws_sett_prioritet(text, int, text);
create function public.ws_sett_prioritet(p_kode text, p_navn text, p_nr int, p_prioritet text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
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
  p_kode text, p_navn text, p_nr int, p_god_nok boolean,
  p_forenkling text default '', p_validering text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
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

drop function if exists public.ws_status();
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
      from public.ws_gruppe), '[]'::json)
  ));
end $$;

grant execute on function public.ws_sett_prioritet(text, text, int, text) to anon, authenticated;
grant execute on function public.ws_sett_gruppe(text, text, int, boolean, text, text) to anon, authenticated;
grant execute on function public.ws_status(text) to anon, authenticated;
grant execute on function public.ws_sett_kode(text) to authenticated;

notify pgrst, 'reload schema';
