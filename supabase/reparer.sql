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
              'min_profil','sett_navn'))
        or (n.nspname = 'private' and p.proname in
             ('workshop_by_code','participant_ok','meg','parse_frist'))
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
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  return json_build_object(
    'workshop', (select name from public.workshops where id = v_ws),
    'meg', v_pid,
    'hypotheses', coalesce((
      select json_agg(json_build_object(
        'id', h.id, 'nr', h.nr, 'tekst', h.tekst, 'kriterium', h.kriterium,
        'kilde', h.kilde, 'eier', h.eier,
        'frist', to_char(h.frist, 'YYYY-MM-DD'),
        'type', h.type, 'status', h.status,
        'status_notat', h.status_notat,
        'status_endret', to_char(h.status_endret, 'YYYY-MM-DD'),
        'status_av', sp.name,
        'publisert', h.publisert,
        'by', p.name, 'by_id', h.created_by,
        'created_at', h.created_at) order by h.publisert desc, h.nr, h.created_at)
      from public.hypotheses h
      left join public.participants p  on p.id  = h.created_by
      left join public.participants sp on sp.id = h.status_av
      where h.workshop_id = v_ws and h.deleted_at is null
        and (h.publisert or h.created_by = v_pid)), '[]'::json),
    -- E-post sendes bevisst ikke ut. Vurderingene er anonyme utad, og adressen
    -- skal ikke bli bakveien til hvem som stemte hva.
    'ratings', coalesce((
      select json_agg(json_build_object('h', r.hypothesis_id, 'p', r.participant_id, 'k', r.k, 'u', r.u))
      from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json)
  );
end $$;

create function public.add_hypothesis(
  p_tekst text, p_kriterium text, p_type text, p_kilde text default '',
  p_eier text default '', p_frist text default null, p_publisert boolean default true)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_nr int; v_id uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  if coalesce(p_publisert, true) then
    perform 1 from public.workshops where id = v_ws for update;  -- serialiserer nummerering
    select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  end if;
  insert into public.hypotheses (workshop_id, nr, tekst, kriterium, type, kilde, eier, frist,
                                 created_by, publisert)
  values (v_ws, v_nr, btrim(p_tekst), coalesce(btrim(p_kriterium), ''), p_type,
          left(coalesce(btrim(p_kilde), ''), 300),
          left(coalesce(btrim(p_eier), ''), 200),
          private.parse_frist(p_frist), v_pid, coalesce(p_publisert, true))
  returning id into v_id;
  return json_build_object('id', v_id, 'nr', v_nr);
end $$;

create function public.publish_hypothesis(p_id uuid)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_nr int; v_eier uuid; v_pub boolean; v_tekst text;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select created_by, publisert, tekst into v_eier, v_pub, v_tekst
    from public.hypotheses where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
  if v_eier is distinct from v_pid then
    raise exception 'Du kan bare publisere dine egne kladder' using errcode = '42501';
  end if;
  if v_pub then
    return json_build_object('id', p_id, 'nr', (select nr from public.hypotheses where id = p_id));
  end if;
  if btrim(coalesce(v_tekst, '')) = '' then
    raise exception 'Hypotesen kan ikke være tom' using errcode = '23514';
  end if;
  perform 1 from public.workshops where id = v_ws for update;
  select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  update public.hypotheses set nr = v_nr, publisert = true, updated_at = now()
   where id = p_id;
  return json_build_object('id', p_id, 'nr', v_nr);
end $$;

create function public.update_hypothesis(p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null,
  p_status text default null, p_kilde text default null,
  p_eier text default null, p_frist text default null,
  p_status_notat text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_naa text; v_ny text; v_notat text; v_endret boolean;
        v_pub boolean; v_av uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;

  select status, publisert, created_by into v_naa, v_pub, v_av
    from public.hypotheses
   where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
  -- En kladd tilhører den som skriver den. Den er usynlig for andre, så dette
  -- er et vern mot et kall som går utenom klienten, ikke mot et feiltrykk.
  if not v_pub and v_av is distinct from v_pid then
    raise exception 'Kladden tilhører noen andre' using errcode = '42501';
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

-- Sletting er eierens egen. Hypoteser fra deltakere som er borte (created_by
-- blir null når en deltaker fjernes) kan ingen slette lenger — det er med vilje,
-- siden alternativet er at hvem som helst kan rydde i andres grunnlag.
create function public.delete_hypothesis(p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_av uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select created_by into v_av from public.hypotheses
   where id = p_id and workshop_id = v_ws and deleted_at is null;
  if not found then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
  if v_av is distinct from v_pid then
    raise exception 'Du kan bare slette hypoteser du har lagt inn selv' using errcode = '42501';
  end if;
  update public.hypotheses set deleted_at = now(), updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

create function public.rate_hypothesis(p_id uuid, p_k smallint, p_u smallint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
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

-- ---------- rettigheter ----------
-- anon får ingenting. Uten sesjon finnes det ingen identitet å handle som.
revoke all on function public.min_profil() from public, anon;
revoke all on function public.sett_navn(text) from public, anon;
revoke all on function public.get_board() from public, anon;
revoke all on function public.add_hypothesis(text,text,text,text,text,text,boolean) from public, anon;
revoke all on function public.publish_hypothesis(uuid) from public, anon;
revoke all on function public.update_hypothesis(uuid,text,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.delete_hypothesis(uuid) from public, anon;
revoke all on function public.rate_hypothesis(uuid,smallint,smallint) from public, anon;

grant execute on function public.min_profil() to authenticated;
grant execute on function public.sett_navn(text) to authenticated;
grant execute on function public.get_board() to authenticated;
grant execute on function public.add_hypothesis(text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.publish_hypothesis(uuid) to authenticated;
grant execute on function public.update_hypothesis(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.delete_hypothesis(uuid) to authenticated;
grant execute on function public.rate_hypothesis(uuid,smallint,smallint) to authenticated;

-- RLS skal fortsatt være på, uten policies. All tilgang går via funksjonene.
alter table public.workshops    enable row level security;
alter table public.participants enable row level security;
alter table public.hypotheses   enable row level security;
alter table public.ratings      enable row level security;
revoke all on public.workshops, public.participants, public.hypotheses, public.ratings from anon, authenticated;

-- ---------- be PostgREST lese skjemaet på nytt ----------
notify pgrst, 'reload schema';
