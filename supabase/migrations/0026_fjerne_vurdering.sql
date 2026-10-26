-- 0026: en vurdering skal kunne fjernes.
--
-- Vurderingsbildet blar automatisk videre når du har valgt. Det er riktig når
-- du har ti minutter på ni hypoteser — men det gjør også at et feiltrykk
-- umiddelbart forsvinner ut av syne, og at du må lete deg tilbake for å rette.
-- Uten en vei ut blir stemmen stående som om den var ment.
--
-- Tom prioritet sletter raden. Det er bevisst ikke en fjerde kategori: «ingen
-- mening» skal ikke telles som et standpunkt, og tredelingen i agendaen
-- (må / bør / kan vente) skal stå urørt. Den som ikke har svart, er ganske
-- enkelt ikke med i tellingen for den hypotesen — og `deltakere` teller
-- fortsatt alle som har avgitt minst én vurdering.

drop function if exists public.ws_sett_prioritet(text, text, int, text);
create function public.ws_sett_prioritet(p_kode text, p_navn text, p_nr int, p_prioritet text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.ws_sjekk(p_kode);
  if coalesce(btrim(p_navn), '') = '' then
    raise exception 'Mangler navn' using errcode = '23514';
  end if;

  -- Angret vurdering: raden skal bort, ikke stå igjen med en gammel verdi.
  if coalesce(btrim(p_prioritet), '') = '' then
    delete from public.ws_prioritet where navn = btrim(p_navn) and nr = p_nr;
    return;
  end if;

  if p_prioritet not in ('maa','bor','vent') then
    raise exception 'Ukjent prioritet: %', p_prioritet using errcode = '23514';
  end if;

  insert into public.ws_prioritet (navn, nr, prioritet)
  values (btrim(p_navn), p_nr, p_prioritet)
  on conflict (navn, nr) do update
    set prioritet = excluded.prioritet, oppdatert = now();
end $$;

grant execute on function public.ws_sett_prioritet(text, text, int, text) to anon, authenticated;

notify pgrst, 'reload schema';
