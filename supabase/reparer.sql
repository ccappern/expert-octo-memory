-- REPARER: bringer databasen til riktig tilstand uansett hvilke migrasjoner som
-- er kjørt før.
--
-- Bakgrunn: flere migrasjoner endrer signaturen på de samme funksjonene. Kjøres
-- de i feil rekkefølge, eller hoppes én over, blir gamle utgaver liggende igjen
-- som overlast. PostgREST svarer da «Could not find the function ... in the
-- schema cache» selv om funksjonen tilsynelatende finnes.
--
-- Dette skriptet dropper ALLE utgaver av de offentlige funksjonene og bygger dem
-- opp igjen i endelig form, legger til kolonner som måtte mangle, og retter
-- begrensningene. Data røres ikke: hypoteser, deltakere og vurderinger blir
-- stående.
--
-- MERK: fra og med 0015 er tilgangsmodellen Supabase Auth. Identiteten er den
-- verifiserte e-postadressen i sesjonen; passkoden og deltakertokenet er borte.
-- Skriptet oppretter IKKE brukere i auth.users — de lages med Admin API-et, og
-- invitasjonslista ligger i 0016.
--
-- Trygt å kjøre flere ganger.

do $$
begin
  if to_regclass('public.workshops') is null then
    raise exception 'Fant ikke public.workshops. Kjør 0001_init.sql først.';
  end if;
end $$;

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

-- ---------- kolonner som kan mangle ----------
alter table public.hypotheses add column if not exists kilde text not null default '';
alter table public.hypotheses add column if not exists eier  text not null default '';
alter table public.hypotheses add column if not exists frist date;
alter table public.hypotheses add column if not exists status_notat text not null default '';
alter table public.hypotheses add column if not exists status_endret timestamptz;
alter table public.hypotheses add column if not exists status_av uuid references public.participants(id);
alter table public.hypotheses add column if not exists publisert boolean not null default true;

-- Kladd har ikke nummer. Nummeret er den felles referansen i møtet, og skal
-- ikke brukes opp av noe de andre ikke kan se.
alter table public.hypotheses alter column nr drop not null;
create index if not exists hypotheses_kladd_idx
  on public.hypotheses (workshop_id, created_by) where not publisert;

alter table public.hypotheses drop constraint if exists hypotheses_kilde_check;
alter table public.hypotheses add  constraint hypotheses_kilde_check check (char_length(kilde) <= 300);
alter table public.hypotheses drop constraint if exists hypotheses_eier_check;
alter table public.hypotheses add  constraint hypotheses_eier_check  check (char_length(eier)  <= 200);
alter table public.hypotheses drop constraint if exists hypotheses_status_notat_check;
alter table public.hypotheses add  constraint hypotheses_status_notat_check check (char_length(status_notat) <= 500);

alter table public.hypotheses drop constraint if exists hypotheses_type_check;
alter table public.hypotheses add  constraint hypotheses_type_check
  check (type in ('verdi','gjennom','levedykt','aksept','tilp'));

-- ---------- leveransene (0017) ----------
-- Leveransene erstatter typene som grupperingen registeret rapporteres på. De
-- ligger som DATA og ikke som konstant i klienten, i motsetning til EIERE:
-- kilden på Confluence har ødelagt nummerering og uavklart overlapp, så lista
-- kommer til å bli rettet flere ganger. Med slug som nøkkel og nr som vanlig
-- kolonne koster hver retting null migrasjoner.
create table if not exists public.deliverables (
  id          uuid primary key default extensions.gen_random_uuid(),
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  slug        text not null,
  nr          int  not null,
  label       text not null,
  hint        text not null default '',
  valgbar     boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint deliverables_slug_key  unique (workshop_id, slug),
  constraint deliverables_slug_form check (slug ~ '^[a-z][a-z0-9_]{1,30}$'),
  constraint deliverables_label_len check (char_length(label) between 1 and 120),
  constraint deliverables_hint_len  check (char_length(hint) <= 300),
  constraint deliverables_nr_check  check (nr between 1 and 99)
);
-- Indeks og ikke unique: «bytt plass på 2 og 3» ville kollidert midt i
-- oppdateringen hvis nummeret måtte være unikt hele veien.
create index if not exists deliverables_nr_idx on public.deliverables (workshop_id, nr);

alter table public.hypotheses add column if not exists leveranse   text;
alter table public.hypotheses add column if not exists leveranse_2 text;

-- Sammensatt fremmednøkkel mot (workshop_id, slug) gjør to jobber: den hindrer
-- at en hypotese peker på en leveranse i en annen workshop, og den NEKTER
-- sletting av en leveranse som er i bruk. Med `on delete set null` ville
-- hypoteser mistet leveransen stille, og ingen oppdager det før rapporten er feil.
alter table public.hypotheses drop constraint if exists hypotheses_leveranse_fk;
alter table public.hypotheses add  constraint hypotheses_leveranse_fk
  foreign key (workshop_id, leveranse) references public.deliverables (workshop_id, slug);
alter table public.hypotheses drop constraint if exists hypotheses_leveranse_2_fk;
alter table public.hypotheses add  constraint hypotheses_leveranse_2_fk
  foreign key (workshop_id, leveranse_2) references public.deliverables (workshop_id, slug);

alter table public.hypotheses drop constraint if exists hypotheses_leveranse_2_check;
alter table public.hypotheses add  constraint hypotheses_leveranse_2_check
  check (leveranse_2 is null or (leveranse is not null and leveranse_2 <> leveranse));

create index if not exists hypotheses_leveranse_idx
  on public.hypotheses (workshop_id, leveranse) where deleted_at is null;

-- ---------- administratorer (0017) ----------
alter table public.participants add column if not exists admin boolean not null default false;

-- ---------- resultatvisning (0018) ----------
-- Sperren mot å se gruppens tall mens man stemmer. Den ligger her og ikke i
-- klienten fordi den publiserbare nøkkelen er kjent: filtrerer vi bare i
-- nettleseren, kan hvem som helst lese tallene via RPC-en.
alter table public.workshops add column if not exists resultatvisning text not null default 'etter_stemme';
alter table public.workshops drop constraint if exists workshops_resultatvisning_check;
alter table public.workshops add  constraint workshops_resultatvisning_check
  check (resultatvisning in ('lukket','etter_stemme','apent'));

-- ---------- trakten: oppgave, grupper og det endelige tallet (0021) ----------
-- Taktpinnen. Ligger her og ikke i klienten av samme grunn som
-- resultatvisning: den publiserbare nøkkelen er kjent.
alter table public.workshops add column if not exists oppgave text not null default 'individuell';
alter table public.workshops drop constraint if exists workshops_oppgave_check;
alter table public.workshops add  constraint workshops_oppgave_check
  check (oppgave in ('les','individuell','gruppe','staaved','plenum','oppgaver'));
alter table public.workshops add column if not exists oppgaver_apnet_ubehandlet int;

-- Gruppene er DATA og ikke en konstant i klienten: inndelingen endrer seg i det
-- noen melder forfall om morgenen, og det skal ikke koste en migrasjon.
create table if not exists public.groups (
  id          uuid primary key default extensions.gen_random_uuid(),
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  slug        text not null,
  nr          int  not null,
  label       text not null,
  sted        text not null default '',
  frist_tekst text not null default '',
  leder       uuid references public.participants(id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint groups_slug_key unique (workshop_id, slug)
);

alter table public.participants add column if not exists group_id uuid
  references public.groups(id) on delete set null;

alter table public.hypotheses add column if not exists i_gruppearbeid boolean not null default false;
alter table public.hypotheses add column if not exists endelig_k smallint;
alter table public.hypotheses add column if not exists endelig_u smallint;
alter table public.hypotheses add column if not exists gruppesprik boolean not null default false;

-- Egen tabell, IKKE en group_id-kolonne på ratings: alt som leser ratings antar
-- at én rad er én persons stemme, og de stedene som glemmes å filtrere ville
-- blandet gruppetall inn i individsnittet.
create table if not exists public.group_ratings (
  hypothesis_id uuid not null references public.hypotheses(id) on delete cascade,
  group_id      uuid not null references public.groups(id) on delete cascade,
  k smallint check (k between 0 and 10),
  u smallint check (u between 0 and 10),
  hensyn text not null default '',
  satt_av uuid references public.participants(id),
  updated_at timestamptz not null default now(),
  primary key (hypothesis_id, group_id)
);

alter table public.hypotheses add column if not exists plenum_utfall text;
alter table public.hypotheses drop constraint if exists hypotheses_plenum_utfall_check;
alter table public.hypotheses add  constraint hypotheses_plenum_utfall_check
  check (plenum_utfall in ('justert','staar','eskalert'));
alter table public.hypotheses add column if not exists plenum_notat text not null default '';
alter table public.hypotheses add column if not exists plenum_av uuid references public.participants(id);
alter table public.hypotheses add column if not exists plenum_tid timestamptz;

-- ---------- identitet: verifisert e-post ----------
alter table public.participants add column if not exists epost text;
alter table public.participants drop constraint if exists participants_epost_check;
alter table public.participants add  constraint participants_epost_check
  check (epost is null or (epost = lower(btrim(epost)) and position('@' in epost) > 1));

-- Partiell indeks: «Forprosjektdokumentasjonen» er ikke en person, men eier
-- hypoteser. Den skal stå uten e-post og aldri kunne logge inn.
drop index if exists participants_epost_idx;
create unique index participants_epost_idx
  on public.participants (workshop_id, epost) where epost is not null;

-- Hver enhet har nå sin egen auth-sesjon. Én token_hash-kolonne rommet ett
-- token, så en ny enhet logget ut den forrige.
alter table public.participants drop column if exists token_hash;
alter table public.workshops    drop column if exists code_hash;

-- ---------- skala 1-10, med vern mot dobbel omregning ----------
create table if not exists private.meta (
  key text primary key, value text not null, satt timestamptz not null default now()
);
revoke all on private.meta from public, anon, authenticated;

alter table public.ratings drop constraint if exists ratings_k_check;
alter table public.ratings drop constraint if exists ratings_u_check;

do $$
declare v_n int; v_maks int;
begin
  select greatest(coalesce(max(k),0), coalesce(max(u),0)) into v_maks from public.ratings;
  if exists (select 1 from private.meta where key='skala' and value='10') then
    raise notice 'Skala: allerede 1-10, ingen omregning.';
  elsif v_maks > 5 then
    -- Verdier over 5 finnes allerede, så skalaen er i praksis 1-10 selv om
    -- markøren mangler. Omregning ville ødelagt tallene.
    insert into private.meta(key,value) values ('skala','10')
      on conflict (key) do update set value='10', satt=now();
    raise notice 'Skala: fant verdier over 5, antar 1-10. Ingen omregning.';
  else
    -- 0 er «vet ikke» og ligger utenfor skalaen. Omregningsformelen ville gjort
    -- den til -1 og brutt CHECK-en, så den må stå urørt gjennom konverteringen.
    update public.ratings
       set k = case when k is null or k = 0 then k else round((k-1)*9.0/4.0)+1 end,
           u = case when u is null or u = 0 then u else round((u-1)*9.0/4.0)+1 end,
           updated_at = now();
    get diagnostics v_n = row_count;
    insert into private.meta(key,value) values ('skala','10')
      on conflict (key) do update set value='10', satt=now();
    raise notice 'Skala: regnet om % vurderinger fra 1-5 til 1-10.', v_n;
  end if;
end $$;

-- 0 = «vet ikke»: et eksplisitt svar om at man ikke har grunnlag for å mene noe,
-- til forskjell fra NULL som betyr at aksen ikke er besvart. Verdien holdes
-- utenfor snittet i klienten, men telles og vises for seg.
alter table public.ratings add constraint ratings_k_check check (k between 0 and 10);
alter table public.ratings add constraint ratings_u_check check (u between 0 and 10);

-- ---------- fjern alle gamle utgaver av funksjonene ----------
do $$
declare r record; v_n int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where (n.nspname = 'public'  and p.proname in
             ('join_workshop','get_board','add_hypothesis','update_hypothesis',
              'delete_hypothesis','rate_hypothesis','publish_hypothesis',
              'min_profil','sett_navn',
              'admin_sett_leveranse','admin_slett_leveranse','admin_add_hypothesis',
              'admin_sett_hypothesis_leveranse','admin_arkiver_hypothesis',
              'admin_gjenopprett_hypothesis','admin_arkiv',
              'admin_sett_resultatvisning',
              'rate_group_hypothesis','admin_sett_oppgave','admin_sett_gruppe',
              'admin_slett_gruppe','admin_sett_gruppeleder','admin_foresla_grupper',
              'admin_lagre_grupper','admin_sett_deltaker_gruppe','admin_deltakere',
              'admin_kvitter_plenum'))
        or (n.nspname = 'private' and p.proname in
             ('workshop_by_code','participant_ok','meg','meg_admin','parse_frist',
              'steg_nr','sprik','frys_utvalg','beregn_endelig'))
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
    v_n := v_n + 1;
  end loop;
  raise notice 'Fjernet % funksjonsutgaver.', v_n;
end $$;

-- ---------- interne hjelpere ----------
-- Alt annet hviler på denne. Den oversetter auth-sesjonen til en deltakerrad,
-- og er samtidig tilgangskontrollen: er du ikke invitert, finnes du ikke her.
create function private.meg(out v_pid uuid, out v_ws uuid)
language plpgsql stable security definer set search_path = '' as $$
declare v_epost text; v_n int;
begin
  v_epost := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  if v_epost = '' then
    raise exception 'Du er ikke logget inn' using errcode = '28000';
  end if;

  select count(*) into v_n from public.participants p where p.epost = v_epost;
  if v_n = 0 then
    raise exception 'Adressen % er ikke invitert til workshopen', v_epost
      using errcode = '42501';
  end if;
  if v_n > 1 then
    raise exception 'Adressen % finnes i flere workshoper. Funksjonene må utvides med valg av workshop.', v_epost
      using errcode = '21000';
  end if;

  select p.id, p.workshop_id into v_pid, v_ws
    from public.participants p where p.epost = v_epost;
end $$;

create function private.parse_frist(p text)
returns date language plpgsql immutable set search_path = '' as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  if btrim(p) !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Fristen må være på formen ÅÅÅÅ-MM-DD' using errcode = '22007';
  end if;
  return btrim(p)::date;
end $$;

-- Tilgangskontrollen for backend. admin.html ligger offentlig lesbar på GitHub
-- Pages og skjuler bare knapper; det er denne funksjonen som faktisk stenger
-- døra. Hver admin-RPC starter med den.
create function private.meg_admin(out v_pid uuid, out v_ws uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  if not exists (select 1 from public.participants where id = v_pid and admin) then
    raise exception 'Du har ikke tilgang til backend' using errcode = '42501';
  end if;
end $$;

-- Trakten er ordnet, og nesten hver sperre er «fra og med dette steget». Et
-- tall er lettere å sammenlikne enn en liste over tillatte strenger.
create function private.steg_nr(p_oppgave text)
returns int language sql immutable set search_path = '' as $$
  select case p_oppgave
           when 'les' then 1 when 'individuell' then 2 when 'gruppe' then 3
           when 'staaved' then 4 when 'plenum' then 5 when 'oppgaver' then 6
           else 0 end;
$$;

-- Samme mål på uenighet som «Uenige» bruker i klienten (ANDEL 0,30, SPRIK 4,
-- MIN_STEMMER 3, grensen ved 5,5). Ligger her fordi både utvalgsfrysingen og
-- bruddlinjene i gruppeforslaget må bruke nøyaktig samme mål — to
-- implementasjoner ville drevet fra hverandre uten at noen oppdaget det.
create function private.sprik(p_hid uuid)
returns numeric language plpgsql stable security definer set search_path = '' as $$
declare v_best numeric := 0; v_n int; v_lav int; v_spenn numeric; v_akse int;
begin
  for v_akse in 1..2 loop
    select count(*), count(*) filter (where v <= 5.5), max(v) - min(v)
      into v_n, v_lav, v_spenn
      from (select case when v_akse = 1 then r.k else r.u end::numeric as v
              from public.ratings r
             where r.hypothesis_id = p_hid and r.k >= 1 and r.u >= 1) x;
    if v_n >= 3
       and least(v_lav, v_n - v_lav)::numeric / v_n >= 0.30
       and v_spenn >= 4
       and v_spenn > v_best then
      v_best := v_spenn;
    end if;
  end loop;
  return v_best;
end $$;

-- Utvalget gruppene faktisk rekker. Tid er ikke den egentlige spaken, omfang
-- er: gruppa som skal rekke alt slutter å tenke rundt nummer ni.
create function private.frys_utvalg(p_ws uuid, p_maks int)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_n int;
begin
  update public.hypotheses set i_gruppearbeid = false where workshop_id = p_ws;

  with kandidater as (
    select h.id,
           private.sprik(h.id) as sprik,
           (select avg(r.k) from public.ratings r
             where r.hypothesis_id = h.id and r.k >= 1) as snitt_k,
           (select count(*) from public.ratings r
             where r.hypothesis_id = h.id) as n_alle,
           (select count(*) from public.ratings r
             where r.hypothesis_id = h.id and (r.k = 0 or r.u = 0)) as n_vet
      from public.hypotheses h
     where h.workshop_id = p_ws and h.deleted_at is null and h.publisert
  )
  update public.hypotheses h set i_gruppearbeid = true
    from (
      select id from kandidater
       where sprik > 0 or snitt_k > 5.5 or (n_alle > 0 and n_vet = n_alle)
       order by (sprik > 0) desc, sprik desc, snitt_k desc nulls last
       limit p_maks) v
   where h.id = v.id;

  get diagnostics v_n = row_count;
  if v_n > 0 then return; end if;

  -- Tynne data: klokka 14.55 har kanskje ti av 21 rukket gjennom, og da
  -- kvalifiserer ingen hypotese på uenighet. Et tomt utvalg er verre enn et
  -- grovt, så det velges på kritikalitet alene i stedet.
  update public.hypotheses h set i_gruppearbeid = true
    from (
      select h2.id
        from public.hypotheses h2
       where h2.workshop_id = p_ws and h2.deleted_at is null and h2.publisert
       order by (select avg(r.k) from public.ratings r
                  where r.hypothesis_id = h2.id and r.k >= 1) desc nulls last,
                h2.nr
       limit p_maks) v
   where h.id = v.id;
end $$;

-- Tallet trakten ender på. Standardverdien regnes ut og forhandles ikke;
-- fasilitator overstyrer bare der rommet faktisk gjorde noe ('justert').
create function private.beregn_endelig(p_ws uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.hypotheses h set
    -- 0 er «vet ikke» og ikke et lavt tall. En gruppe med k = 0 teller ikke i
    -- snittet, og en hypotese der ALLE gruppene svarte «vet ikke» får null —
    -- ikke et oppdiktet snitt. Den hører i bunken «Ingen kan svare».
    endelig_k = case when h.i_gruppearbeid
                     then (select round(avg(gr.k)) from public.group_ratings gr
                            where gr.hypothesis_id = h.id and gr.k >= 1)
                     else (select round(avg(r.k)) from public.ratings r
                            where r.hypothesis_id = h.id and r.k >= 1) end,
    endelig_u = case when h.i_gruppearbeid
                     then (select round(avg(gr.u)) from public.group_ratings gr
                            where gr.hypothesis_id = h.id and gr.u >= 1)
                     else (select round(avg(r.u)) from public.ratings r
                            where r.hypothesis_id = h.id and r.u >= 1) end,
    gruppesprik = h.i_gruppearbeid and (
      select count(distinct (gr.k > 5.5, gr.u > 5.5)) > 1
        from public.group_ratings gr
       where gr.hypothesis_id = h.id and gr.k >= 1 and gr.u >= 1)
  where h.workshop_id = p_ws and h.deleted_at is null;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;

-- ---------- offentlige RPC-er ----------
create function public.min_profil()
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  return json_build_object(
    'participant_id', v_pid,
    'navn',     (select name from public.participants where id = v_pid),
    'epost',    (select epost from public.participants where id = v_pid),
    'workshop', (select name from public.workshops where id = v_ws));
end $$;

-- Navnet kommer fra invitasjonslista, men folk må kunne rette sitt eget: lista
-- er skrevet av én person og inneholder både feilstavinger og adresser uten
-- kjent navn.
create function public.sett_navn(p_navn text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_navn text;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  v_navn := btrim(coalesce(p_navn, ''));
  if char_length(v_navn) < 1 or char_length(v_navn) > 60 then
    raise exception 'Navnet må være mellom 1 og 60 tegn' using errcode = '23514';
  end if;
  update public.participants set name = v_navn where id = v_pid;
end $$;

create function public.get_board()
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_modus text; v_oppgave text; v_steg int; v_gid uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select resultatvisning, oppgave into v_modus, v_oppgave
    from public.workshops where id = v_ws;
  v_steg := private.steg_nr(v_oppgave);
  select group_id into v_gid from public.participants where id = v_pid;

  return json_build_object(
    'workshop', (select name from public.workshops where id = v_ws),
    'meg', v_pid,
    'admin', coalesce((select admin from public.participants where id = v_pid), false),
    'resultatvisning', v_modus,
    'oppgave', v_oppgave,
    'deltakere_totalt', (select count(*) from public.participants
                          where workshop_id = v_ws and epost is not null),
    'leveranser', coalesce((
      select json_agg(json_build_object(
        'slug', d.slug, 'nr', d.nr, 'label', d.label,
        'hint', d.hint, 'valgbar', d.valgbar) order by d.nr, d.label)
      from public.deliverables d where d.workshop_id = v_ws), '[]'::json),

    -- endelig_k/u holdes tilbake til plenum. Sendes de tidligere, finnes
    -- konklusjonen på skjermen før rommet har bygget den — nøyaktig feilen §2
    -- beskriver, bare med et annet tall.
    'hypotheses', coalesce((
      select json_agg(json_build_object(
        'id', h.id, 'nr', h.nr, 'tekst', h.tekst, 'kriterium', h.kriterium,
        'kilde', h.kilde, 'eier', h.eier,
        'frist', to_char(h.frist, 'YYYY-MM-DD'),
        'type', h.type,
        'leveranse', h.leveranse, 'leveranse_2', h.leveranse_2,
        'status', h.status,
        'status_notat', h.status_notat,
        'status_endret', to_char(h.status_endret, 'YYYY-MM-DD'),
        'status_av', sp.name,
        'publisert', h.publisert,
        'i_gruppearbeid', h.i_gruppearbeid,
        'endelig_k', case when v_steg >= 5 then h.endelig_k end,
        'endelig_u', case when v_steg >= 5 then h.endelig_u end,
        'gruppesprik', case when v_steg >= 5 then h.gruppesprik else false end,
        'plenum_utfall', case when v_steg >= 5 then h.plenum_utfall end,
        'plenum_notat', case when v_steg >= 5 then h.plenum_notat else '' end,
        'created_at', h.created_at) order by h.nr, h.created_at)
      from public.hypotheses h
      left join public.participants sp on sp.id = h.status_av
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json),

    -- Tellingene er bevisst skilt fra radene. De skal kunne vises også når
    -- verdiene holdes tilbake, og de røper ingen retning.
    'tellinger', coalesce((
      select json_agg(json_build_object(
        'h', h.id,
        'n', (select count(*) from public.ratings r
               where r.hypothesis_id = h.id and r.k >= 1 and r.u >= 1),
        'vetIkke', (select count(*) from public.ratings r
                     where r.hypothesis_id = h.id and (r.k = 0 or r.u = 0))))
      from public.hypotheses h
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json),

    -- Ankringssperren gjaldt mens folk stemte individuelt. Fra og med steg 3 er
    -- individtallene tvert imot det gruppa skal diskutere ut fra (§6): startet
    -- to av dem på 3 og 9, må spriket ligge på bordet.
    'ratings', coalesce((
      select json_agg(json_build_object('h', r.hypothesis_id, 'p', r.participant_id, 'k', r.k, 'u', r.u))
      from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
      where h.workshop_id = v_ws and h.deleted_at is null
        and (
          v_steg >= 3
          or v_modus = 'apent'
          or r.participant_id = v_pid
          or (v_modus = 'etter_stemme' and exists (
                select 1 from public.ratings meg
                 where meg.hypothesis_id = r.hypothesis_id
                   and meg.participant_id = v_pid
                   and meg.k is not null and meg.u is not null))
        )), '[]'::json),

    'deltakere_vurdert', (
      select count(distinct r.participant_id)
        from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
       where h.workshop_id = v_ws and h.deleted_at is null),

    -- Medlemslista sendes til alle: den ER beskjeden på storskjermen i §6, og
    -- hvem som sitter hvor røper ingen vurdering.
    'grupper', coalesce((
      select json_agg(json_build_object(
        'slug', g.slug, 'nr', g.nr, 'label', g.label,
        'sted', g.sted, 'frist_tekst', g.frist_tekst,
        'leder', g.leder,
        'leder_navn', (select name from public.participants where id = g.leder),
        'medlemmer', coalesce((
          select json_agg(json_build_object('id', p.id, 'navn', p.name) order by p.name)
          from public.participants p where p.group_id = g.id), '[]'::json))
        order by g.nr, g.slug)
      from public.groups g where g.workshop_id = v_ws), '[]'::json),

    'min_gruppe', (select json_build_object(
        'slug', g.slug, 'label', g.label, 'sted', g.sted,
        'frist_tekst', g.frist_tekst,
        'leder', g.leder,
        'leder_navn', (select name from public.participants where id = g.leder),
        'er_leder', g.leder = v_pid)
      from public.groups g where g.id = v_gid),

    -- Egen gruppe i steg 3, alle fra og med plenum. Gallerivandringen er fjernet
    -- (§4): gruppene ser hverandre først i plenum, og det er plenums
    -- åpningsbilde — ikke noe klienten velger å tegne eller la være.
    'gruppe_ratings', coalesce((
      select json_agg(json_build_object(
        'h', gr.hypothesis_id, 'g', g.slug, 'k', gr.k, 'u', gr.u,
        'hensyn', gr.hensyn, 'av', sp.name, 'tid', gr.updated_at))
      from public.group_ratings gr
      join public.groups g on g.id = gr.group_id
      join public.hypotheses h on h.id = gr.hypothesis_id
      left join public.participants sp on sp.id = gr.satt_av
      where h.workshop_id = v_ws and h.deleted_at is null
        and (v_steg >= 5 or (v_steg = 3 and gr.group_id = v_gid))), '[]'::json),

    -- Telles i databasen av samme grunn som deltakere_vurdert: klienten ser
    -- bare sin egen gruppes rader og ville alltid rapportert én gruppe.
    -- Nevneren er utvalget, ikke registeret — «9 av 11» er framgang, mens
    -- «9 av 23» leses som fiasko selv når gruppa gjorde nøyaktig det den skulle.
    'gruppe_framdrift', coalesce((
      select json_agg(json_build_object(
        'g', g.slug,
        'n', (select count(*) from public.group_ratings gr
               join public.hypotheses h on h.id = gr.hypothesis_id
              where gr.group_id = g.id and h.i_gruppearbeid
                and h.deleted_at is null and gr.k is not null and gr.u is not null),
        'av', (select count(*) from public.hypotheses h
                where h.workshop_id = v_ws and h.deleted_at is null and h.i_gruppearbeid))
        order by g.nr, g.slug)
      from public.groups g where g.workshop_id = v_ws), '[]'::json),

    -- §9: oppgavelista er konklusjonen og sendes ikke før steget er åpnet.
    -- Null og ikke tom liste: klienten skal kunne skille «ikke åpnet ennå» fra
    -- «åpnet, men ingenting havnet i bunken».
    'oppgaver', case when v_oppgave = 'oppgaver' then (
      select json_build_object(
        'ubehandlet', (select oppgaver_apnet_ubehandlet from public.workshops where id = v_ws),
        -- Må leveres: begge akser over grensen. Dette er forprosjektets jobb.
        'maa', coalesce((select json_agg(h.id order by h.nr) from public.hypotheses h
                 where h.workshop_id = v_ws and h.deleted_at is null
                   and h.endelig_k > 5.5 and h.endelig_u > 5.5), '[]'::json),
        -- Ingen kan svare: en frist hjelper ikke når ingen vet hvor svaret
        -- finnes. Bunken bør helst være tom; er den det ikke, er den det
        -- viktigste forprosjektet har å rapportere.
        'ingen_svar', coalesce((select json_agg(h.id order by h.nr) from public.hypotheses h
                 where h.workshop_id = v_ws and h.deleted_at is null
                   and (h.endelig_k is null or h.endelig_u is null)), '[]'::json),
        'eskalert', coalesce((select json_agg(h.id order by h.nr) from public.hypotheses h
                 where h.workshop_id = v_ws and h.deleted_at is null
                   and h.plenum_utfall = 'eskalert'), '[]'::json),
        -- Kategorien tredelingen mangler (§1), og den mest verdifulle for
        -- styringsgruppen. Skal ikke presses inn i «skal ikke leveres».
        'premiss', coalesce((select json_agg(h.id order by h.nr) from public.hypotheses h
                 where h.workshop_id = v_ws and h.deleted_at is null
                   and h.endelig_k > 5.5 and h.endelig_u <= 5.5), '[]'::json))
    ) end
  );
end $$;

-- Deltakerne kan fortsatt rette tekst, eier, frist og status. Det er selve
-- arbeidet i workshopen. Leveransekoblingen flyttes bare fra backend.
create function public.update_hypothesis(p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null,
  p_status text default null, p_kilde text default null,
  p_eier text default null, p_frist text default null,
  p_status_notat text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_naa text; v_ny text; v_notat text; v_endret boolean;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;

  select status into v_naa
    from public.hypotheses
   where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;

  v_ny     := coalesce(p_status, v_naa);
  v_endret := v_ny is distinct from v_naa;
  v_notat  := left(btrim(coalesce(p_status_notat, '')), 500);

  -- Avklart status flytter hypotesen inn i grunnlaget for anbefalingen. Da må
  -- det stå hva som avgjorde det. Kravet gjelder bare når statusen faktisk
  -- settes, ikke ved retting av tekst eller eier på en allerede avklart rad.
  if v_endret and v_ny in ('bekreftet','avkreftet') and v_notat = '' then
    raise exception 'Skriv inn hva som avgjorde det før du setter % status',
      case v_ny when 'bekreftet' then 'bekreftet' else 'avkreftet' end
      using errcode = '23514';
  end if;

  update public.hypotheses set
    tekst     = coalesce(btrim(p_tekst), tekst),
    kriterium = coalesce(btrim(p_kriterium), kriterium),
    type      = coalesce(p_type, type),
    status    = v_ny,
    kilde     = coalesce(left(btrim(p_kilde), 300), kilde),
    eier      = coalesce(left(btrim(p_eier), 200), eier),
    frist     = case when p_frist is null then frist else private.parse_frist(p_frist) end,
    status_notat  = case when v_endret then v_notat
                         when p_status_notat is null then status_notat
                         else v_notat end,
    status_endret = case when v_endret then now() else status_endret end,
    status_av     = case when v_endret then v_pid else status_av end,
    updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

-- delete_hypothesis er fjernet i 0017. Deltakerne oppretter ikke lenger egne
-- hypoteser, så det finnes ikke noe «mitt» å slette. Fjerning skjer fra backend
-- som arkivering (admin_arkiver_hypothesis), der vurderingene blir stående.

create function public.rate_hypothesis(p_id uuid, p_k smallint, p_u smallint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_oppgave text;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select oppgave into v_oppgave from public.workshops where id = v_ws;
  if v_oppgave <> 'individuell' then
    raise exception 'Den individuelle vurderingen er lukket' using errcode = '42501';
  end if;
  -- Kladd kan ikke vurderes, heller ikke av den som eier den: snittet skal
  -- starte først når alle ser den samme teksten.
  if not exists (select 1 from public.hypotheses
                  where id = p_id and workshop_id = v_ws and deleted_at is null and publisert) then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
  if p_k is null and p_u is null then
    delete from public.ratings where hypothesis_id = p_id and participant_id = v_pid;
  else
    insert into public.ratings (hypothesis_id, participant_id, k, u, updated_at)
    values (p_id, v_pid, p_k, p_u, now())
    on conflict (hypothesis_id, participant_id)
    do update set k = excluded.k, u = excluded.u, updated_at = now();
  end if;
end $$;

-- ---------- backend ----------
-- Alle starter med meg_admin(). Rekkefølgen er ikke kosmetisk: feiler den,
-- kjøres ingenting av det under.
create function public.admin_sett_leveranse(
  p_slug text, p_nr int, p_label text, p_hint text default '', p_valgbar boolean default true)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_slug text;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  v_slug := lower(btrim(coalesce(p_slug, '')));
  if v_slug !~ '^[a-z][a-z0-9_]{1,30}$' then
    raise exception 'Kortnavnet må være 2-31 tegn: små bokstaver, tall og understrek'
      using errcode = '23514';
  end if;
  insert into public.deliverables (workshop_id, slug, nr, label, hint, valgbar)
  values (v_ws, v_slug, p_nr, btrim(p_label), left(btrim(coalesce(p_hint,'')), 300),
          coalesce(p_valgbar, true))
  on conflict (workshop_id, slug) do update
    set nr = excluded.nr, label = excluded.label,
        hint = excluded.hint, valgbar = excluded.valgbar;
  return json_build_object('slug', v_slug);
end $$;

create function public.admin_slett_leveranse(p_slug text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_n int;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  -- Fremmednøkkelen ville stoppet dette uansett, men med en melding ingen kan
  -- handle på. Her får du vite hvor mange som må flyttes først.
  select count(*) into v_n from public.hypotheses
   where workshop_id = v_ws and deleted_at is null
     and (leveranse = p_slug or leveranse_2 = p_slug);
  if v_n > 0 then
    raise exception '% hypoteser er koblet til leveransen. Flytt dem før du sletter den.', v_n
      using errcode = '23503';
  end if;
  delete from public.deliverables where workshop_id = v_ws and slug = p_slug;
end $$;

create function public.admin_add_hypothesis(
  p_tekst text, p_kriterium text default '', p_leveranse text default null,
  p_leveranse_2 text default null, p_type text default 'verdi',
  p_kilde text default '', p_eier text default '', p_frist text default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_nr int; v_id uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  if btrim(coalesce(p_tekst, '')) = '' then
    raise exception 'Hypotesen kan ikke være tom' using errcode = '23514';
  end if;
  perform 1 from public.workshops where id = v_ws for update;  -- serialiserer nummerering
  select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  insert into public.hypotheses (workshop_id, nr, tekst, kriterium, type,
                                 leveranse, leveranse_2, kilde, eier, frist,
                                 created_by, publisert)
  values (v_ws, v_nr, btrim(p_tekst), left(coalesce(btrim(p_kriterium), ''), 1000),
          coalesce(p_type, 'verdi'),
          nullif(btrim(coalesce(p_leveranse, '')), ''),
          nullif(btrim(coalesce(p_leveranse_2, '')), ''),
          left(coalesce(btrim(p_kilde), ''), 300),
          left(coalesce(btrim(p_eier), ''), 200),
          private.parse_frist(p_frist), v_pid, true)
  returning id into v_id;
  return json_build_object('id', v_id, 'nr', v_nr);
end $$;

create function public.admin_sett_hypothesis_leveranse(
  p_id uuid, p_leveranse text, p_leveranse_2 text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  update public.hypotheses
     set leveranse   = nullif(btrim(coalesce(p_leveranse, '')), ''),
         leveranse_2 = nullif(btrim(coalesce(p_leveranse_2, '')), ''),
         updated_at  = now()
   where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
end $$;

-- Arkivering, ikke sletting. En ekte delete ville tatt med seg alle stemmene
-- via cascade, og det finnes ingen angreknapp midt i en workshop.
create function public.admin_arkiver_hypothesis(p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  update public.hypotheses set deleted_at = now(), updated_at = now()
   where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke, eller er allerede arkivert' using errcode = 'P0002';
  end if;
end $$;

create function public.admin_gjenopprett_hypothesis(p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  update public.hypotheses set deleted_at = null, updated_at = now()
   where id = p_id and workshop_id = v_ws and deleted_at is not null;
  if not found then
    raise exception 'Hypotesen finnes ikke, eller er ikke arkivert' using errcode = 'P0002';
  end if;
end $$;

-- Arkivet er bare synlig for admin. Deltakerne skal ikke se et lag med
-- hypoteser som er tatt ut av grunnlaget.
create function public.admin_arkiv()
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  return coalesce((
    select json_agg(json_build_object(
      'id', h.id, 'nr', h.nr, 'tekst', h.tekst, 'leveranse', h.leveranse,
      'arkivert', to_char(h.deleted_at, 'YYYY-MM-DD')) order by h.deleted_at desc)
    from public.hypotheses h
    where h.workshop_id = v_ws and h.deleted_at is not null), '[]'::json);
end $$;

create function public.admin_sett_resultatvisning(p_modus text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  if p_modus not in ('lukket','etter_stemme','apent') then
    raise exception 'Ukjent modus: %', p_modus using errcode = '23514';
  end if;
  update public.workshops set resultatvisning = p_modus where id = v_ws;
end $$;

-- §5: bare gruppelederen skriver. group_ratings har én rad per hypotese per
-- gruppe, og appen tegner alt på nytt hvert fjerde sekund — kunne alle fem
-- skrive, ville to som drar på samme skala overskrive hverandre uten at noen
-- merker det, og gruppa ville diskutert videre ut fra et tall ingen satte.
--
-- Det fjerner samtidighetsproblemet i stedet for å løse det, og er bedre
-- fasilitering: fire som hver drar i sin slider forhandler ikke, de stemmer.
-- Merk at det IKKE finnes noen p_forrige — den optimistiske låsen utgår med
-- skriveretten.
create function public.rate_group_hypothesis(
  p_id uuid, p_k smallint, p_u smallint, p_hensyn text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_oppgave text; v_gid uuid; v_leder uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select oppgave into v_oppgave from public.workshops where id = v_ws;
  -- Gruppas forslag er endelig når steg 3 lukkes. Uten dette ville et av
  -- grunnlagene for plenum kunne flytte seg mens plenum pågår.
  if v_oppgave <> 'gruppe' then
    raise exception 'Gruppearbeidet er ikke åpent' using errcode = '42501';
  end if;

  select group_id into v_gid from public.participants where id = v_pid;
  if v_gid is null then
    raise exception 'Du er ikke satt i en gruppe ennå, si fra til fasilitator'
      using errcode = '42501';
  end if;

  select leder into v_leder from public.groups where id = v_gid;
  if v_leder is distinct from v_pid then
    raise exception 'Bare gruppelederen fører for gruppen' using errcode = '42501';
  end if;

  if not exists (select 1 from public.hypotheses
                  where id = p_id and workshop_id = v_ws and deleted_at is null
                    and publisert and i_gruppearbeid) then
    raise exception 'Hypotesen er ikke i gruppearbeidet' using errcode = 'P0002';
  end if;

  if p_k is null and p_u is null and coalesce(btrim(p_hensyn), '') = '' then
    delete from public.group_ratings where hypothesis_id = p_id and group_id = v_gid;
  else
    insert into public.group_ratings (hypothesis_id, group_id, k, u, hensyn, satt_av, updated_at)
    values (p_id, v_gid, p_k, p_u, left(coalesce(btrim(p_hensyn), ''), 500), v_pid, now())
    on conflict (hypothesis_id, group_id) do update
      set k = excluded.k, u = excluded.u,
          -- null betyr «rørte ikke feltet»: hensynet skrives med debounce fra
          -- klienten og skal ikke nulles av et tastetrykk på skalaen.
          hensyn = case when p_hensyn is null then public.group_ratings.hensyn
                        else excluded.hensyn end,
          satt_av = v_pid, updated_at = now();
  end if;
end $$;

-- ---------- backend: taktpinnen ----------

-- Tre overganger gjør arbeid, og arbeidet må skje i SAMME transaksjon som
-- byttet (§11). Skjer det i et eget kall etterpå, finnes det et vindu der
-- rommet står i gruppearbeid uten utvalg — og 21 personer ser en tom liste.
create function public.admin_sett_oppgave(p_modus text, p_maks int default 10)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pid uuid; v_ws uuid; v_fra text; v_fra_nr int; v_til_nr int;
  v_maks int := greatest(coalesce(p_maks, 10), 1);
  v_n int; v_advarsel text := ''; v_melding text := '';
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  if private.steg_nr(p_modus) = 0 then
    raise exception 'Ukjent oppgave: %', p_modus using errcode = '23514';
  end if;
  select oppgave into v_fra from public.workshops where id = v_ws for update;
  v_fra_nr := private.steg_nr(v_fra);
  v_til_nr := private.steg_nr(p_modus);

  -- Rygging: verktøyet flytter ikke seg selv, og det nekter heller ikke
  -- fasilitator å blad tilbake. Men hun skal få vite hva som står lenger
  -- framme, med antall — ellers oppdages tapet først når noen klager.
  if v_til_nr < v_fra_nr then
    select count(*) into v_n
      from public.group_ratings gr join public.hypotheses h on h.id = gr.hypothesis_id
     where h.workshop_id = v_ws;
    if v_til_nr < 3 and v_n > 0 then
      -- Utvalget tines IKKE automatisk. Det ville kastet gruppenes arbeid.
      -- i_gruppearbeid fryses på nytt først ved neste lukking av steg 2.
      v_advarsel := format(
        '%s gruppevurderinger er lagret. Utvalget står urørt; fryses det på nytt ved neste '
        || 'inngang til gruppearbeid, blir rader som faller ut foreldreløse.', v_n);
    end if;
    if v_fra_nr >= 5 then
      -- plenum_utfall nullstilles ikke: en kvittering er fasilitators handling
      -- og skal ikke forsvinne fordi hun bladde feil vei.
      v_advarsel := btrim(v_advarsel || ' Endelig tall beregnes på nytt ved neste inngang til plenum.');
    end if;
  end if;

  if p_modus = 'gruppe' then
    perform private.frys_utvalg(v_ws, v_maks);
    select count(*) into v_n from public.hypotheses
     where workshop_id = v_ws and deleted_at is null and i_gruppearbeid;
    v_melding := format('%s hypoteser går til gruppearbeid.', v_n);

  elsif p_modus = 'plenum' then
    perform private.beregn_endelig(v_ws);
    select count(*) into v_n from public.hypotheses
     where workshop_id = v_ws and deleted_at is null and gruppesprik;
    v_melding := format('%s hypoteser har gruppesprik og står på agendaen.', v_n);

  elsif p_modus = 'oppgaver' then
    -- Sperren er MYK, og det er en beslutning (§9). Med ti minutters plenum er
    -- sannsynligheten for at rommet ikke kommer gjennom alle ikke liten, den er
    -- høy — og en hard sperre ville betydd at neste bolk starter med en låst
    -- skjerm. Antallet lagres i stedet, og følger med ut i eksporten.
    -- Hopper fasilitator rett fra gruppearbeid til oppgavelista, finnes det
    -- ikke noe endelig tall å lese bunkene av. Da regnes det ut her i stedet
    -- for å la lista stå tom — steget skal åpnes uansett.
    if v_fra_nr < 5 then
      perform private.beregn_endelig(v_ws);
    end if;
    select count(*) into v_n from public.hypotheses
     where workshop_id = v_ws and deleted_at is null
       and gruppesprik and plenum_utfall is null;
    update public.workshops set oppgaver_apnet_ubehandlet = v_n where id = v_ws;
    v_melding := case when v_n = 0 then 'Alle saker er behandlet.'
                 else format('Oppgavelista er produsert uten at %s saker er behandlet.', v_n) end;
  end if;

  update public.workshops set oppgave = p_modus where id = v_ws;
  return json_build_object('oppgave', p_modus, 'fra', v_fra,
                           'melding', v_melding, 'advarsel', nullif(v_advarsel, ''));
end $$;

-- ---------- backend: grupper ----------
create function public.admin_sett_gruppe(
  p_slug text, p_nr int default null, p_label text default null,
  p_sted text default null, p_frist_tekst text default null, p_leder uuid default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_slug text; v_id uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  v_slug := lower(btrim(coalesce(p_slug, '')));
  if v_slug !~ '^[a-z][a-z0-9_]{0,30}$' then
    raise exception 'Kortnavnet må være 1-31 tegn: små bokstaver, tall og understrek'
      using errcode = '23514';
  end if;
  insert into public.groups (workshop_id, slug, nr, label, sted, frist_tekst, leder)
  values (v_ws, v_slug, coalesce(p_nr, 1), coalesce(nullif(btrim(p_label), ''), upper(v_slug)),
          coalesce(left(btrim(p_sted), 120), ''),
          coalesce(left(btrim(p_frist_tekst), 60), ''), p_leder)
  on conflict (workshop_id, slug) do update
    set nr          = coalesce(p_nr, public.groups.nr),
        label       = coalesce(nullif(btrim(p_label), ''), public.groups.label),
        sted        = coalesce(left(btrim(p_sted), 120), public.groups.sted),
        frist_tekst = coalesce(left(btrim(p_frist_tekst), 60), public.groups.frist_tekst),
        leder       = coalesce(p_leder, public.groups.leder)
  returning id into v_id;
  return json_build_object('slug', v_slug, 'id', v_id);
end $$;

create function public.admin_slett_gruppe(p_slug text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_id uuid; v_n int;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  select id into v_id from public.groups where workshop_id = v_ws and slug = p_slug;
  if v_id is null then
    raise exception 'Gruppen finnes ikke' using errcode = 'P0002';
  end if;
  -- Gruppens vurderinger forsvinner med cascade. Det finnes ingen angreknapp
  -- midt i en workshop, så fasilitator skal få vite det før hun sletter.
  select count(*) into v_n from public.group_ratings where group_id = v_id;
  if v_n > 0 then
    raise exception 'Gruppen har % vurderinger. Tøm dem først hvis du virkelig vil slette.', v_n
      using errcode = '23503';
  end if;
  delete from public.groups where id = v_id;
end $$;

-- Egen funksjon, ikke et felt i et redigeringsskjema (§6). Når bare én kan
-- skrive, er en leder som faller fra den eneste nye enkeltfeilkilden
-- skriveretten innfører — og da er tjue minutter gruppearbeid tapt mens
-- fasilitator leter.
create function public.admin_sett_gruppeleder(p_slug text, p_pid uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_id uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  select id into v_id from public.groups where workshop_id = v_ws and slug = p_slug;
  if v_id is null then
    raise exception 'Gruppen finnes ikke' using errcode = 'P0002';
  end if;
  -- Lederen må være i gruppa. En leder som sitter ved et annet bord fører ikke
  -- i pennen for noen, og feilen ville først vist seg som en gruppe som står.
  if p_pid is not null and not exists (
       select 1 from public.participants where id = p_pid and group_id = v_id) then
    raise exception 'Lederen må være medlem av gruppen' using errcode = '23514';
  end if;
  update public.groups set leder = p_pid where id = v_id;
end $$;

create function public.admin_sett_deltaker_gruppe(p_pid uuid, p_slug text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_id uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  if p_slug is not null then
    select id into v_id from public.groups where workshop_id = v_ws and slug = p_slug;
    if v_id is null then
      raise exception 'Gruppen finnes ikke' using errcode = 'P0002';
    end if;
  end if;
  update public.participants set group_id = v_id
   where id = p_pid and workshop_id = v_ws;
  if not found then
    raise exception 'Deltakeren finnes ikke' using errcode = 'P0002';
  end if;
  -- Flyttes lederen ut, skal gruppa stå uten leder og ikke med en leder som
  -- sitter et annet sted. Fasilitator ser da at noen må utpekes.
  update public.groups set leder = null where leder = p_pid and id is distinct from v_id;
end $$;

create function public.admin_deltakere()
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  return coalesce((
    select json_agg(json_build_object(
      'id', p.id, 'navn', p.name, 'epost', p.epost, 'admin', p.admin,
      'gruppe', (select g.slug from public.groups g where g.id = p.group_id),
      'vurdert', (select count(*) from public.ratings r
                   join public.hypotheses h on h.id = r.hypothesis_id
                  where r.participant_id = p.id and h.deleted_at is null))
      order by p.name)
    from public.participants p where p.workshop_id = v_ws), '[]'::json);
end $$;

-- §6: funksjonen RETURNERER et forslag og SKRIVER INGENTING. Fasilitator ser
-- inndelingen, drar om på den, og lagrer først da — en knapp som fordeler 21
-- personer rett i databasen er en knapp ingen tør trykke på.
--
-- Hvorfor det blandes etter uenighet og ikke etter enighet: homogene grupper
-- produserer et tall på tretti sekunder og lærer ingenting, uenigheten må da
-- løses i plenum med 21 til stede, og enighet korrelerer med arbeidsgiver — en
-- inndeling som speiler organisasjonskartet kan ikke vise hva det mangler.
create function public.admin_foresla_grupper(
  p_antall int default 4, p_seed int default 0, p_med_admin boolean default false)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pid uuid; v_ws uuid; v_brudd uuid[]; v_melding text := '';
  v_antall int := greatest(coalesce(p_antall, 4), 1);
  -- Byttet heter v_bytt og ikke r: plpgsql lar variabelnavn skygge for
  -- tabellaliaser, og «r» er aliaset ratings bruker i hver eneste delspørring.
  v_runde int; v_bytter int := 0; v_bytt record;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;

  -- setseed gjelder resten av sesjonen, så den må settes og ikke antas.
  -- p_seed er «Foreslå på nytt»: ser fasilitator at to som nettopp kranglet
  -- havnet sammen, skal hun kunne trekke om.
  perform setseed(least(abs(coalesce(p_seed, 0)) % 1000 / 1000.0, 0.999999));

  -- Trinn 1: bruddlinjene — de hypotesene rommet er mest delt om.
  select coalesce(array_agg(id order by s desc), '{}'::uuid[]) into v_brudd
    from (select h.id, private.sprik(h.id) as s
            from public.hypotheses h
           where h.workshop_id = v_ws and h.deleted_at is null and h.publisert
           order by 2 desc limit 5) q
   where q.s > 0;

  -- Er det færre enn tre bruddlinjer, finnes det ingen reell uenighet å spre.
  -- Mandag er dette et SANNSYNLIG utfall — tjue minutter gir tynne data — så
  -- meldingen må være tydelig og ikke en fotnote.
  if coalesce(array_length(v_brudd, 1), 0) < 3 then
    v_melding := format(
      'Fant bare %s hypotese(r) rommet er tydelig delt om. Gruppene er fordelt tilfeldig. '
      || 'Se over inndelingen for hånd før du lagrer.',
      coalesce(array_length(v_brudd, 1), 0));
    v_brudd := '{}'::uuid[];
  end if;

  drop table if exists pg_temp.forslag;
  create temp table forslag as
  with d as (
    select p.id, p.name,
           split_part(coalesce(p.epost, ''), '@', 2) as domene,
           -- Trinn 2: posisjon — hvor høyt hun legger seg på bruddlinjene samlet.
           (select avg((r.k + r.u) / 2.0) from public.ratings r
             where r.participant_id = p.id and r.hypothesis_id = any(v_brudd)
               and r.k >= 1 and r.u >= 1) as pos,
           (select count(*) from public.ratings r
             join public.hypotheses h on h.id = r.hypothesis_id
            where r.participant_id = p.id and h.deleted_at is null) as vurdert
      from public.participants p
      -- «Forprosjektdokumentasjonen» har ingen e-post og er ikke en person.
      -- Tas den med, får én gruppe et medlem som aldri møter opp.
     where p.workshop_id = v_ws and p.epost is not null
       and (coalesce(p_med_admin, false) or not p.admin)
  ), o as (
    -- De som ikke stemte har ingen posisjon og legges bakerst. Fordi draftet
    -- fortsetter gjennom dem, fordeles de jevnt i stedet for å klumpe seg i
    -- siste gruppe. Mandag er det ikke et særtilfelle, men en stor andel.
    select d.*, row_number() over (
             order by (pos is null), pos desc, random()) - 1 as rn
      from d
  )
  -- Trinn 3: seriedraft. 1-2-3-4, så 4-3-2-1, så om igjen. Det garanterer at
  -- hver gruppe spenner over hele spekteret, og kan forklares på én setning —
  -- fasilitator kan forsvare inndelingen hvis noen spør hvorfor de havnet der.
  select o.id, o.name, o.domene, o.pos, o.vurdert, o.rn,
         case when (o.rn / v_antall) % 2 = 0
              then (o.rn % v_antall) else v_antall - 1 - (o.rn % v_antall) end as gnr
    from o;

  -- Trinn 4: rett opp virksomhetsklumper. Domenet er en TILNÆRMING og ikke en
  -- sannhet — konsulenter på kundens domene gir feil klumper — så dette er en
  -- justering som gjerne kan bomme, aldri en betingelse som kan blokkere.
  for v_runde in 1..20 loop
    select a.id as a_id, a.gnr as a_g, b.id as b_id, b.gnr as b_g into v_bytt
      from pg_temp.forslag a
      join pg_temp.forslag b
        on b.gnr <> a.gnr and b.domene <> a.domene
       and abs(coalesce(b.pos, 0) - coalesce(a.pos, 0)) <= 1
     where a.domene <> ''
       and (select count(*) from pg_temp.forslag x
             where x.gnr = a.gnr and x.domene = a.domene) >= 3
       and (select count(*) from pg_temp.forslag x
             where x.gnr = b.gnr and x.domene = a.domene) = 0
       and (select count(*) from pg_temp.forslag x
             where x.gnr = a.gnr and x.domene = b.domene) = 0
     order by abs(coalesce(b.pos, 0) - coalesce(a.pos, 0))
     limit 1;
    exit when not found;
    update pg_temp.forslag set gnr = v_bytt.b_g where id = v_bytt.a_id;
    update pg_temp.forslag set gnr = v_bytt.a_g where id = v_bytt.b_id;
    v_bytter := v_bytter + 1;
  end loop;

  return json_build_object(
    'melding', nullif(v_melding, ''),
    'bruddlinjer', coalesce((select json_agg(h.nr order by h.nr) from public.hypotheses h
                              where h.id = any(v_brudd)), '[]'::json),
    'bytter', v_bytter,
    'grupper', coalesce((
      select json_agg(j order by (j->>'nr')::int) from (
        select json_build_object(
          'nr', (f.gnr + 1)::int,
          'slug', lower(chr((97 + f.gnr)::int)),
          'label', 'Gruppe ' || chr((65 + f.gnr)::int),
          -- Lederen er den som har vurdert flest i steg 2, uavgjort brutt av
          -- p_seed. IKKE ansiennitet: utpekingen skal belønne at noen har lest,
          -- og ikke peke ut den mest seniore — det ville gjenskapt nøyaktig den
          -- feilmodusen blandede grupper er bygget for å unngå.
          'leder', (select x.id from pg_temp.forslag x where x.gnr = f.gnr
                     order by x.vurdert desc, random() limit 1),
          -- Lav spenn er et varsel om at gruppa blir ferdig på fem minutter
          -- uten å ha diskutert noe. Står ved siden av lagreknappen, ikke bak
          -- en fane: det er den eneste tilbakemeldingen fasilitator rekker å
          -- lese mens rommet venter.
          'spenn', round(coalesce(max(f.pos) - min(f.pos), 0), 1),
          'virksomheter', count(distinct nullif(f.domene, '')),
          'antall', count(*),
          'uten_stemme', count(*) filter (where f.pos is null),
          'medlemmer', json_agg(json_build_object(
            'id', f.id, 'navn', f.name, 'domene', nullif(f.domene, ''),
            'posisjon', round(f.pos, 1), 'vurdert', f.vurdert)
            order by f.pos desc nulls last)) as j
        from pg_temp.forslag f group by f.gnr) q), '[]'::json));
end $$;

-- Hele inndelingen i ÉN transaksjon. Et utkast lagret rad for rad: 21 kall som
-- kan bli delvis anvendt hvis nettet glipper, og da står rommet med en halv
-- inndeling klokka 14.57.
create function public.admin_lagre_grupper(p_json json)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; g json; v_gid uuid; v_slug text; v_n int := 0; v_m int := 0;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;

  -- Nullstilles først: lagringen er hele inndelingen, ikke et tillegg. Uten
  -- dette ville en person som ble tatt UT av forslaget blitt stående i sin
  -- gamle gruppe, og ingen ville oppdaget det før hun satt ved feil bord.
  update public.participants set group_id = null where workshop_id = v_ws;

  for g in select * from json_array_elements(p_json) loop
    v_slug := lower(btrim(coalesce(g->>'slug', '')));
    if v_slug = '' then
      raise exception 'Hver gruppe må ha et kortnavn' using errcode = '23514';
    end if;
    insert into public.groups (workshop_id, slug, nr, label, sted, frist_tekst)
    values (v_ws, v_slug, coalesce((g->>'nr')::int, 1),
            coalesce(nullif(btrim(g->>'label'), ''), upper(v_slug)),
            coalesce(left(btrim(g->>'sted'), 120), ''),
            coalesce(left(btrim(g->>'frist_tekst'), 60), ''))
    on conflict (workshop_id, slug) do update
      set nr          = excluded.nr,
          label       = excluded.label,
          sted        = excluded.sted,
          frist_tekst = excluded.frist_tekst
    returning id into v_gid;
    v_n := v_n + 1;

    update public.participants set group_id = v_gid
     where workshop_id = v_ws
       and id in (select (value #>> '{}')::uuid from json_array_elements(coalesce(g->'medlemmer', '[]'::json)));
    get diagnostics v_m = row_count;

    -- Lederen settes etter medlemmene, ellers avvises hun av kravet om at
    -- lederen må være i gruppa.
    update public.groups set leder = nullif(btrim(g->>'leder'), '')::uuid where id = v_gid;
  end loop;

  -- En gruppe hvis leder havnet et annet sted i omfordelingen skal stå uten
  -- leder, ikke med en som sitter ved et annet bord.
  update public.groups g set leder = null
   where g.workshop_id = v_ws and g.leder is not null
     and not exists (select 1 from public.participants p
                      where p.id = g.leder and p.group_id = g.id);

  return json_build_object(
    'grupper', v_n,
    'utildelte', (select count(*) from public.participants
                   where workshop_id = v_ws and epost is not null and group_id is null));
end $$;

-- ---------- backend: plenum ----------
-- 'justert' skriver endelig_k/u. De to andre utfallene rører ikke tallet:
-- 'staar' betyr at rommet valgte å leve med spriket, og 'eskalert' at
-- spørsmålet går videre som et spørsmål og ikke som en oppgave.
create function public.admin_kvitter_plenum(
  p_id uuid, p_utfall text, p_notat text default '',
  p_k smallint default null, p_u smallint default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg_admin() m;
  if p_utfall is not null and p_utfall not in ('justert','staar','eskalert') then
    raise exception 'Ukjent utfall: %', p_utfall using errcode = '23514';
  end if;
  if p_utfall = 'justert' and (p_k is null or p_u is null) then
    raise exception 'Justert plassering krever både kritikalitet og usikkerhet'
      using errcode = '23514';
  end if;
  update public.hypotheses set
    plenum_utfall = p_utfall,
    plenum_notat  = left(coalesce(btrim(p_notat), ''), 500),
    plenum_av     = case when p_utfall is null then null else v_pid end,
    plenum_tid    = case when p_utfall is null then null else now() end,
    endelig_k     = case when p_utfall = 'justert' then p_k else endelig_k end,
    endelig_u     = case when p_utfall = 'justert' then p_u else endelig_u end,
    updated_at    = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
end $$;

-- ---------- rettigheter ----------
-- anon får ingenting. Uten sesjon finnes det ingen identitet å handle som.
revoke all on function public.min_profil() from public, anon;
revoke all on function public.sett_navn(text) from public, anon;
revoke all on function public.get_board() from public, anon;
revoke all on function public.update_hypothesis(uuid,text,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.rate_hypothesis(uuid,smallint,smallint) from public, anon;
revoke all on function public.admin_sett_leveranse(text,int,text,text,boolean) from public, anon;
revoke all on function public.admin_slett_leveranse(text) from public, anon;
revoke all on function public.admin_add_hypothesis(text,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.admin_sett_hypothesis_leveranse(uuid,text,text) from public, anon;
revoke all on function public.admin_arkiver_hypothesis(uuid) from public, anon;
revoke all on function public.admin_gjenopprett_hypothesis(uuid) from public, anon;
revoke all on function public.admin_arkiv() from public, anon;
revoke all on function public.admin_sett_resultatvisning(text) from public, anon;
revoke all on function public.rate_group_hypothesis(uuid,smallint,smallint,text) from public, anon;
revoke all on function public.admin_sett_oppgave(text,int) from public, anon;
revoke all on function public.admin_sett_gruppe(text,int,text,text,text,uuid) from public, anon;
revoke all on function public.admin_slett_gruppe(text) from public, anon;
revoke all on function public.admin_sett_gruppeleder(text,uuid) from public, anon;
revoke all on function public.admin_foresla_grupper(int,int,boolean) from public, anon;
revoke all on function public.admin_lagre_grupper(json) from public, anon;
revoke all on function public.admin_sett_deltaker_gruppe(uuid,text) from public, anon;
revoke all on function public.admin_deltakere() from public, anon;
revoke all on function public.admin_kvitter_plenum(uuid,text,text,smallint,smallint) from public, anon;

grant execute on function public.min_profil() to authenticated;
grant execute on function public.sett_navn(text) to authenticated;
grant execute on function public.get_board() to authenticated;
grant execute on function public.update_hypothesis(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.rate_hypothesis(uuid,smallint,smallint) to authenticated;
grant execute on function public.rate_group_hypothesis(uuid,smallint,smallint,text) to authenticated;

-- Admin-RPC-ene er kjørbare for alle innloggede. Det er meg_admin() som avviser
-- dem, ikke rettigheten: en 42501 gir en forståelig feilmelding, mens manglende
-- EXECUTE gir «function does not exist» og sender folk på villspor etter en
-- migrasjon som ikke er kjørt.
grant execute on function public.admin_sett_leveranse(text,int,text,text,boolean) to authenticated;
grant execute on function public.admin_slett_leveranse(text) to authenticated;
grant execute on function public.admin_add_hypothesis(text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_sett_hypothesis_leveranse(uuid,text,text) to authenticated;
grant execute on function public.admin_arkiver_hypothesis(uuid) to authenticated;
grant execute on function public.admin_gjenopprett_hypothesis(uuid) to authenticated;
grant execute on function public.admin_arkiv() to authenticated;
grant execute on function public.admin_sett_resultatvisning(text) to authenticated;
grant execute on function public.admin_sett_oppgave(text,int) to authenticated;
grant execute on function public.admin_sett_gruppe(text,int,text,text,text,uuid) to authenticated;
grant execute on function public.admin_slett_gruppe(text) to authenticated;
grant execute on function public.admin_sett_gruppeleder(text,uuid) to authenticated;
grant execute on function public.admin_foresla_grupper(int,int,boolean) to authenticated;
grant execute on function public.admin_lagre_grupper(json) to authenticated;
grant execute on function public.admin_sett_deltaker_gruppe(uuid,text) to authenticated;
grant execute on function public.admin_deltakere() to authenticated;
grant execute on function public.admin_kvitter_plenum(uuid,text,text,smallint,smallint) to authenticated;

-- RLS skal fortsatt være på, uten policies. All tilgang går via funksjonene.
alter table public.workshops    enable row level security;
alter table public.participants enable row level security;
alter table public.hypotheses   enable row level security;
alter table public.ratings      enable row level security;
alter table public.deliverables enable row level security;
alter table public.groups        enable row level security;
alter table public.group_ratings enable row level security;
revoke all on public.workshops, public.participants, public.hypotheses, public.ratings,
              public.deliverables, public.groups, public.group_ratings from anon, authenticated;

-- ---------- be PostgREST lese skjemaet på nytt ----------
notify pgrst, 'reload schema';
