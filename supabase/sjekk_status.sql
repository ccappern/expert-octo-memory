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

  ('0012', 'get_board tar imot p_pid for egne kladder', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='get_board'
        and pg_get_function_arguments(p.oid) like '%p_pid%')),

  ('0012', 'delete_hypothesis krever eierskap', exists(
     select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='delete_hypothesis'
        and pg_get_functiondef(p.oid) like '%42501%')),

  ('0012', 'kun én utgave av get_board og add_hypothesis', (
     select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('get_board','add_hypothesis')) = 2)
)
select nr            as "Migrasjon",
       hva           as "Hva som sjekkes",
       case when ok then 'OK' else 'MANGLER' end as "Status"
from sjekk
order by nr, hva;
