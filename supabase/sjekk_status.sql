-- Statussjekk. Kjør denne i Supabase SQL Editor når noe ikke virker.
-- Den endrer ingenting, og viser hvilke migrasjoner som faktisk er anvendt.
--
-- Feilen «Could not find the function ... in the schema cache» har to helt ulike
-- årsaker som gir identisk melding:
--   1. migrasjonen er ikke kjørt  -> kolonnen under sier «MANGLER»
--   2. migrasjonen ER kjørt, men PostgREST har gammel cache -> alt sier OK
-- I tilfelle 2: kjør   notify pgrst, 'reload schema';

with sjekk(nr, hva, ok) as (values
  ('0002', 'kilde på hypotesene', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='kilde')),

  ('0004', 'eier og frist på hypotesene', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='eier')
   and exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='frist')),

  ('0004', 'add_hypothesis tar imot p_eier', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='add_hypothesis'
        and pg_get_function_arguments(p.oid) like '%p_eier%')),

  ('0004', 'update_hypothesis tar imot p_eier og p_frist', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='update_hypothesis'
        and pg_get_function_arguments(p.oid) like '%p_eier%'
        and pg_get_function_arguments(p.oid) like '%p_frist%')),

  ('0004', 'get_board leverer eier og frist', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%h.eier%')),

  ('0008', 'fire typer – tilpasningsevne er fjernet igjen', not exists(
     select 1 from pg_constraint
      where conrelid='public.hypotheses'::regclass and contype='c'
        and pg_get_constraintdef(oid) like '%tilp%')),

  ('0007', 'skala 1-10 på vurderingene', exists(
     select 1 from pg_constraint
      where conrelid='public.ratings'::regclass and conname='ratings_k_check'
        and pg_get_constraintdef(oid) like '%10%')),

  ('0009', 'belegg og sporing på statusendringer', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='status_notat')
   and exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='status_endret')
   and exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='status_av')),

  ('0009', 'update_hypothesis tar imot p_status_notat', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='update_hypothesis'
        and pg_get_function_arguments(p.oid) like '%p_status_notat%')),

  ('0009', 'get_board leverer belegget', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%h.status_notat%')),

  ('0012', 'kladd: publisert-kolonne og nullbart nummer', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='publisert')
   and exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='hypotheses' and column_name='nr'
        and is_nullable='YES')),

  ('0012', 'publish_hypothesis finnes', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='publish_hypothesis')),

  -- 0012 sjekket at get_board tok imot p_pid. Fra 0015 kommer identiteten fra
  -- auth-sesjonen i stedet, så funksjonen har ingen parametre i det hele tatt.
  ('0015', 'get_board henter identiteten fra sesjonen, ikke fra parametre', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_function_arguments(p.oid) = '')),

  ('0012', 'delete_hypothesis krever eierskap', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='delete_hypothesis'
        and pg_get_functiondef(p.oid) like '%42501%')),

  ('0012', 'kun én utgave av get_board og add_hypothesis', (
     select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('get_board','add_hypothesis')) = 2),

  -- 0013 endrer bare data, ikke skjema. Derfor sjekkes radene den innførte.
  ('0013', 'eierskap er satt fra H-lista', (
     select count(*) from public.hypotheses
      where deleted_at is null and eier <> '') >= 18),

  ('0013', 'driftsevne og mesh uten anker finnes', (
     select count(*) from public.hypotheses
      where deleted_at is null and tekst in (
        'hver virksomhet har kapasitet til selv å drifte en node og en Varde i daglig drift',
        'deling mellom eksisterende deltakere fortsetter selv om tillitsankeret er utilgjengelig')) = 2),

  ('0013', 'nr. 13 er splittet i kostnad og alternativvurdering', exists(
     select 1 from public.hypotheses where deleted_at is null and tekst =
       'ingen eksisterende løsning dekker behovet godt nok til at det er riktig å bygge nytt')
   and not exists(
     select 1 from public.hypotheses where deleted_at is null and tekst =
       'kostnad og forretningsgevinst forsvarer videreføring, og alternative løsninger ikke dekker behovet like godt')),

  -- Postgres normaliserer «between 0 and 10» til «k >= 0 AND k <= 10», så det er
  -- den formen som må matches her, ikke slik migrasjonen er skrevet.
  ('0014', '«vet ikke» (0) er tillatt på begge aksene', exists(
     select 1 from pg_constraint
      where conrelid='public.ratings'::regclass and conname='ratings_k_check'
        and pg_get_constraintdef(oid) like '%k >= 0%')
   and exists(
     select 1 from pg_constraint
      where conrelid='public.ratings'::regclass and conname='ratings_u_check'
        and pg_get_constraintdef(oid) like '%u >= 0%')),

  ('0015', 'e-post er identiteten', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='participants' and column_name='epost')),

  ('0015', 'passkode og deltakertoken er borte', not exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='participants' and column_name='token_hash')
   and not exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='workshops' and column_name='code_hash')
   and not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='join_workshop')),

  ('0015', 'private.meg() oversetter sesjonen til en deltaker', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname='meg')),

  -- Uten sesjon finnes det ingen identitet å handle som. Får anon fortsatt
  -- kjøre funksjonene, er tavla åpen for hvem som helst med den offentlige
  -- nøkkelen — den ligger i config.js og er ment å være kjent.
  ('0015', 'anon kan ikke kjøre noen av RPC-ene', not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('get_board','add_hypothesis','update_hypothesis',
                          'delete_hypothesis','rate_hypothesis','publish_hypothesis',
                          'min_profil','sett_navn')
        and has_function_privilege('anon', p.oid, 'execute'))),

  ('0015', 'authenticated kan kjøre alle RPC-ene', (
     select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('get_board','add_hypothesis','update_hypothesis',
                          'delete_hypothesis','rate_hypothesis','publish_hypothesis',
                          'min_profil','sett_navn')
        and has_function_privilege('authenticated', p.oid, 'execute')) = 8),

  ('0016', 'de 21 inviterte har e-post', (
     select count(*) from public.participants where epost is not null) >= 21),

  ('0016', 'Forprosjektdokumentasjonen står uten e-post og eier fortsatt hypotesene', exists(
     select 1 from public.participants p
      where p.name = 'Forprosjektdokumentasjonen' and p.epost is null
        and (select count(*) from public.hypotheses h
              where h.created_by = p.id and h.deleted_at is null) > 0)),

  ('0016', 'bare én Christoffer, og ingen testdeltakere igjen', (
     select count(*) from public.participants where name ilike 'christoffer%') = 1
   and not exists(
     select 1 from public.participants
      where name in ('TEST A','TEST B','Test tester','Test Testkraft','Test, Testfirma'))),

  -- Sammenslåingen flytter created_by og status_av FØR tapere slettes. Gjøres
  -- det i motsatt rekkefølge, nulles eierskapet av `on delete set null`, og da
  -- kan ingen lenger redigere eller slette hypotesen.
  ('0016', 'ingen hypoteser mistet eieren i sammenslåingen', not exists(
     select 1 from public.hypotheses where created_by is null and deleted_at is null))
)
select nr            as "Migrasjon",
       hva           as "Hva som sjekkes",
       case when ok then 'OK' else 'MANGLER' end as "Status"
from sjekk
order by nr, hva;
