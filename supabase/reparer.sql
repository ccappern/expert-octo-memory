-- REPARER: bringer databasen til riktig tilstand uansett hvilke migrasjoner som
-- er kjørt før.
--
-- Bakgrunn: migrasjonene 0002, 0004, 0005 og 0006 endrer signaturen på de samme
-- funksjonene. Kjøres de i feil rekkefølge, eller hoppes én over, blir gamle
-- utgaver liggende igjen som overlast. PostgREST svarer da «Could not find the
-- function ... in the schema cache» selv om funksjonen tilsynelatende finnes.
--
-- Dette skriptet dropper ALLE utgaver av de offentlige funksjonene og bygger dem
-- opp igjen i endelig form, legger til kolonner som måtte mangle, og retter
-- begrensningene. Data røres ikke: hypoteser, deltakere og vurderinger blir
-- stående.
--
-- Trygt å kjøre flere ganger. Kjør det i Supabase SQL Editor, i sin helhet.

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

alter table public.hypotheses drop constraint if exists hypotheses_kilde_check;
alter table public.hypotheses add  constraint hypotheses_kilde_check check (char_length(kilde) <= 300);
alter table public.hypotheses drop constraint if exists hypotheses_eier_check;
alter table public.hypotheses add  constraint hypotheses_eier_check  check (char_length(eier)  <= 200);
alter table public.hypotheses drop constraint if exists hypotheses_status_notat_check;
alter table public.hypotheses add  constraint hypotheses_status_notat_check check (char_length(status_notat) <= 500);

alter table public.hypotheses drop constraint if exists hypotheses_type_check;
alter table public.hypotheses add  constraint hypotheses_type_check
  check (type in ('verdi','gjennom','levedykt','aksept','tilp'));

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
    update public.ratings
       set k = case when k is null then null else round((k-1)*9.0/4.0)+1 end,
           u = case when u is null then null else round((u-1)*9.0/4.0)+1 end,
           updated_at = now();
    get diagnostics v_n = row_count;
    insert into private.meta(key,value) values ('skala','10')
      on conflict (key) do update set value='10', satt=now();
    raise notice 'Skala: regnet om % vurderinger fra 1-5 til 1-10.', v_n;
  end if;
end $$;

alter table public.ratings add constraint ratings_k_check check (k between 1 and 10);
alter table public.ratings add constraint ratings_u_check check (u between 1 and 10);

-- ---------- fjern alle gamle utgaver av funksjonene ----------
do $$
declare r record; v_n int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where (n.nspname = 'public'  and p.proname in
             ('join_workshop','get_board','add_hypothesis','update_hypothesis',
              'delete_hypothesis','rate_hypothesis'))
        or (n.nspname = 'private' and p.proname in
             ('workshop_by_code','participant_ok','parse_frist'))
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
    v_n := v_n + 1;
  end loop;
  raise notice 'Fjernet % funksjonsutgaver.', v_n;
end $$;

-- ---------- interne hjelpere ----------
create function private.workshop_by_code(p_code text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid;
begin
  select w.id into v_id from public.workshops w
   where w.code_hash = extensions.crypt(upper(btrim(coalesce(p_code,''))), w.code_hash)
   limit 1;
  if v_id is null then
    raise exception 'Ugyldig workshopkode' using errcode = '28000';
  end if;
  return v_id;
end $$;

create function private.participant_ok(p_ws uuid, p_pid uuid, p_token text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.participants p
     where p.id = p_pid and p.workshop_id = p_ws
       and p.token_hash = encode(extensions.digest(coalesce(p_token,''), 'sha256'), 'hex')
  ) then
    raise exception 'Ukjent deltaker. Logg inn på nytt.' using errcode = '28000';
  end if;
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
create function public.join_workshop(p_code text, p_name text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid; v_token text; v_pid uuid; v_name text;
begin
  v_ws := private.workshop_by_code(p_code);
  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.participants (workshop_id, name, token_hash)
  values (v_ws, btrim(p_name), encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning id into v_pid;
  select name into v_name from public.workshops where id = v_ws;
  return json_build_object('participant_id', v_pid, 'token', v_token, 'workshop', v_name);
end $$;

create function public.get_board(p_code text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_ws uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  return json_build_object(
    'workshop', (select name from public.workshops where id = v_ws),
    'hypotheses', coalesce((
      select json_agg(json_build_object(
        'id', h.id, 'nr', h.nr, 'tekst', h.tekst, 'kriterium', h.kriterium,
        'kilde', h.kilde, 'eier', h.eier,
        'frist', to_char(h.frist, 'YYYY-MM-DD'),
        'type', h.type, 'status', h.status,
        'status_notat', h.status_notat,
        'status_endret', to_char(h.status_endret, 'YYYY-MM-DD'),
        'status_av', sp.name,
        'by', p.name, 'by_id', h.created_by,
        'created_at', h.created_at) order by h.nr)
      from public.hypotheses h
      left join public.participants p  on p.id  = h.created_by
      left join public.participants sp on sp.id = h.status_av
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json),
    'ratings', coalesce((
      select json_agg(json_build_object('h', r.hypothesis_id, 'p', r.participant_id, 'k', r.k, 'u', r.u))
      from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json)
  );
end $$;

create function public.add_hypothesis(p_code text, p_pid uuid, p_token text,
  p_tekst text, p_kriterium text, p_type text, p_kilde text default '',
  p_eier text default '', p_frist text default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid; v_nr int; v_id uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  perform 1 from public.workshops where id = v_ws for update;  -- serialiserer nummerering
  select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  insert into public.hypotheses (workshop_id, nr, tekst, kriterium, type, kilde, eier, frist, created_by)
  values (v_ws, v_nr, btrim(p_tekst), coalesce(btrim(p_kriterium), ''), p_type,
          left(coalesce(btrim(p_kilde), ''), 300),
          left(coalesce(btrim(p_eier), ''), 200),
          private.parse_frist(p_frist), p_pid)
  returning id into v_id;
  return json_build_object('id', v_id, 'nr', v_nr);
end $$;

create function public.update_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null,
  p_status text default null, p_kilde text default null,
  p_eier text default null, p_frist text default null,
  p_status_notat text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid; v_naa text; v_ny text; v_notat text; v_endret boolean;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);

  select status into v_naa from public.hypotheses
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
    status_av     = case when v_endret then p_pid else status_av end,
    updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

create function public.delete_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  update public.hypotheses set deleted_at = now(), updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

create function public.rate_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid,
  p_k smallint, p_u smallint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  if not exists (select 1 from public.hypotheses where id = p_id and workshop_id = v_ws and deleted_at is null) then
    raise exception 'Hypotesen finnes ikke' using errcode = 'P0002';
  end if;
  if p_k is null and p_u is null then
    delete from public.ratings where hypothesis_id = p_id and participant_id = p_pid;
  else
    insert into public.ratings (hypothesis_id, participant_id, k, u, updated_at)
    values (p_id, p_pid, p_k, p_u, now())
    on conflict (hypothesis_id, participant_id)
    do update set k = excluded.k, u = excluded.u, updated_at = now();
  end if;
end $$;

-- ---------- rettigheter ----------
revoke all on function public.join_workshop(text,text) from public;
revoke all on function public.get_board(text) from public;
revoke all on function public.add_hypothesis(text,uuid,text,text,text,text,text,text,text) from public;
revoke all on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text,text) from public;
revoke all on function public.delete_hypothesis(text,uuid,text,uuid) from public;
revoke all on function public.rate_hypothesis(text,uuid,text,uuid,smallint,smallint) from public;

grant execute on function public.join_workshop(text,text) to anon, authenticated;
grant execute on function public.get_board(text) to anon, authenticated;
grant execute on function public.add_hypothesis(text,uuid,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.delete_hypothesis(text,uuid,text,uuid) to anon, authenticated;
grant execute on function public.rate_hypothesis(text,uuid,text,uuid,smallint,smallint) to anon, authenticated;

-- RLS skal fortsatt være på, uten policies. All tilgang går via funksjonene.
alter table public.workshops    enable row level security;
alter table public.participants enable row level security;
alter table public.hypotheses   enable row level security;
alter table public.ratings      enable row level security;
revoke all on public.workshops, public.participants, public.hypotheses, public.ratings from anon, authenticated;

-- ---------- be PostgREST lese skjemaet på nytt ----------
notify pgrst, 'reload schema';
