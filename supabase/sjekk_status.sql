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

  -- 0012 innførte kladd. 0017 avviklet den igjen: hypotesene opprettes nå fra
  -- backend, så publish_hypothesis skal være BORTE. Kolonnen publisert står
  -- igjen fordi indeksene hviler på den.
  ('0017', 'kladd er avviklet – publish_hypothesis er borte', not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('publish_hypothesis','add_hypothesis'))),

  ('0017', 'ingen publiserte hypoteser mangler nummer', not exists(
     select 1 from public.hypotheses
      where deleted_at is null and (nr is null or not publisert))),

  -- 0012 sjekket at get_board tok imot p_pid. Fra 0015 kommer identiteten fra
  -- auth-sesjonen i stedet, så funksjonen har ingen parametre i det hele tatt.
  ('0015', 'get_board henter identiteten fra sesjonen, ikke fra parametre', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_function_arguments(p.oid) = '')),

  -- 0012 krevde eierskap for sletting. 0017 fjernet delete_hypothesis helt:
  -- deltakerne oppretter ikke lenger hypoteser, så det finnes ikke noe «mitt»
  -- å slette. Fjerning skjer som arkivering fra backend.
  ('0017', 'delete_hypothesis er fjernet', not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='delete_hypothesis')),

  ('0012', 'kun én utgave av get_board', (
     select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname = 'get_board') = 1),

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
        and p.proname in ('get_board','update_hypothesis','rate_hypothesis',
                          'min_profil','sett_navn')
        and has_function_privilege('authenticated', p.oid, 'execute')) = 5),

  -- ---------- 0017: leveranser, backend og arkiv ----------
  ('0017', 'leveransene finnes som data', (
     select count(*) from public.deliverables) >= 7),

  ('0017', 'ingen hypotese står uten leveranse', not exists(
     select 1 from public.hypotheses where deleted_at is null and leveranse is null)),

  -- Uten fremmednøkkelen kan en leveranse slettes under føttene på hypotesene,
  -- og tapet oppdages først når en rapport mangler rader.
  ('0017', 'leveransen kan ikke slettes mens den er i bruk', exists(
     select 1 from pg_constraint
      where conrelid='public.hypotheses'::regclass and contype='f'
        and conname='hypotheses_leveranse_fk')),

  ('0017', 'sekundær leveranse krever primær', exists(
     select 1 from pg_constraint
      where conrelid='public.hypotheses'::regclass
        and conname='hypotheses_leveranse_2_check')),

  ('0017', 'admin-kolonnen finnes og minst én administrator er satt', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='participants' and column_name='admin')
   and (select count(*) from public.participants where admin) > 0),

  ('0017', 'private.meg_admin() stenger backend', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname='meg_admin')),

  -- Alle sju admin-RPC-ene må finnes. Mangler én, feiler backend med «function
  -- not found» på akkurat den knappen, og det ser ut som en klientfeil.
  ('0017', 'alle admin-RPC-ene finnes', (
     select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in
        ('admin_sett_leveranse','admin_slett_leveranse','admin_add_hypothesis',
         'admin_sett_hypothesis_leveranse','admin_arkiver_hypothesis',
         'admin_gjenopprett_hypothesis','admin_arkiv')) = 7),

  ('0017', 'anon kan ikke kjøre admin-RPC-ene', not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname like 'admin\_%'
        and has_function_privilege('anon', p.oid, 'execute'))),

  -- ---------- 0018: resultatvisning ----------
  ('0018', 'resultatvisning finnes på workshopen', exists(
     select 1 from information_schema.columns
      where table_schema='public' and table_name='workshops' and column_name='resultatvisning')),

  -- Det er filtreringen i get_board som ER sperren. Ligger den bare i
  -- klienten, kan hvem som helst lese tallene med den publiserbare nøkkelen.
  ('0018', 'get_board holder andres vurderinger tilbake', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%etter_stemme%'
        and pg_get_functiondef(p.oid) like '%tellinger%')),

  ('0018', 'admin_sett_resultatvisning finnes', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='admin_sett_resultatvisning')),

  ('0018', 'navnet på den som la inn hypotesen sendes ikke ut', not exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%''by'', p.name%')),

  ('0020', 'get_board leverer deltakertall', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%deltakere_totalt%'
        and pg_get_functiondef(p.oid) like '%deltakere_vurdert%')),

  ('0017', 'get_board leverer leveranse og admin-flagg', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_functiondef(p.oid) like '%h.leveranse%'
        and pg_get_functiondef(p.oid) like '%''admin''%')),

  ('0016', 'de 21 inviterte har e-post', (
     select count(*) from public.participants where epost is not null) >= 21),

  ('0016', 'Forprosjektdokumentasjonen står uten e-post og eier fortsatt hypotesene', exists(
     select 1 from public.participants p
      where p.name = 'Forprosjektdokumentasjonen' and p.epost is null
        and (select count(*) from public.hypotheses h
              where h.created_by = p.id and h.deleted_at is null) > 0)),

  -- Testdeltakere som eier en hypotese beholdes med vilje: sletting ville nullet
  -- created_by via `on delete set null`, og da kan ingen redigere raden igjen.
  -- «Test tester» eier én arkivert hypotese og blir derfor stående.
  ('0016', 'bare én Christoffer, og ingen testdeltakere med data igjen', (
     select count(*) from public.participants where name ilike 'christoffer%') = 1
   and not exists(
     select 1 from public.participants p
      where p.name in ('TEST A','TEST B','Test tester','Test Testkraft','Test, Testfirma')
        and (exists (select 1 from public.ratings r where r.participant_id = p.id)
          or exists (select 1 from public.hypotheses h
                      where h.created_by = p.id and h.deleted_at is null)))),

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
