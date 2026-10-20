-- Nordlys hypoteseregister
-- Tilgangsmodell: ingen Supabase Auth. Alle tabeller har RLS slått på og ingen policies,
-- så de kan ikke leses eller skrives direkte via API-et. All tilgang går gjennom
-- SECURITY DEFINER-funksjoner som krever workshopkoden, og for skriving også
-- deltakerens hemmelige token (utstedt ved join_workshop).

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------- tabeller ----------
create table public.workshops (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code_hash   text not null,
  created_at  timestamptz not null default now()
);

create table public.participants (
  id           uuid primary key default gen_random_uuid(),
  workshop_id  uuid not null references public.workshops(id) on delete cascade,
  name         text not null check (char_length(btrim(name)) between 1 and 60),
  token_hash   text not null,
  created_at   timestamptz not null default now()
);
create index on public.participants (workshop_id);

create table public.hypotheses (
  id           uuid primary key default gen_random_uuid(),
  workshop_id  uuid not null references public.workshops(id) on delete cascade,
  nr           integer not null,
  tekst        text not null check (char_length(btrim(tekst)) between 1 and 1000),
  kriterium    text not null default '' check (char_length(kriterium) <= 1000),
  type         text not null check (type in ('verdi','gjennom','levedykt','aksept')),
  status       text not null default 'ny' check (status in ('ny','testes','bekreftet','avkreftet')),
  created_by   uuid references public.participants(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (workshop_id, nr)
);
create index on public.hypotheses (created_by);

create table public.ratings (
  hypothesis_id   uuid not null references public.hypotheses(id) on delete cascade,
  participant_id  uuid not null references public.participants(id) on delete cascade,
  k               smallint check (k between 1 and 5),
  u               smallint check (u between 1 and 5),
  updated_at      timestamptz not null default now(),
  primary key (hypothesis_id, participant_id)
);
create index on public.ratings (participant_id);

alter table public.workshops    enable row level security;
alter table public.participants enable row level security;
alter table public.hypotheses   enable row level security;
alter table public.ratings      enable row level security;
revoke all on public.workshops, public.participants, public.hypotheses, public.ratings from anon, authenticated;

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
        'type', h.type, 'status', h.status, 'by', p.name, 'by_id', h.created_by,
        'created_at', h.created_at) order by h.nr)
      from public.hypotheses h left join public.participants p on p.id = h.created_by
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json),
    'ratings', coalesce((
      select json_agg(json_build_object('h', r.hypothesis_id, 'p', r.participant_id, 'k', r.k, 'u', r.u))
      from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json)
  );
end $$;

create function public.add_hypothesis(p_code text, p_pid uuid, p_token text,
  p_tekst text, p_kriterium text, p_type text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid; v_nr int; v_id uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  perform 1 from public.workshops where id = v_ws for update;  -- serialiserer nummerering
  select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  insert into public.hypotheses (workshop_id, nr, tekst, kriterium, type, created_by)
  values (v_ws, v_nr, btrim(p_tekst), coalesce(btrim(p_kriterium), ''), p_type, p_pid)
  returning id into v_id;
  return json_build_object('id', v_id, 'nr', v_nr);
end $$;

create function public.update_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null, p_status text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  update public.hypotheses set
    tekst     = coalesce(btrim(p_tekst), tekst),
    kriterium = coalesce(btrim(p_kriterium), kriterium),
    type      = coalesce(p_type, type),
    status    = coalesce(p_status, status),
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

revoke all on function public.join_workshop(text,text) from public;
revoke all on function public.get_board(text) from public;
revoke all on function public.add_hypothesis(text,uuid,text,text,text,text) from public;
revoke all on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text) from public;
revoke all on function public.delete_hypothesis(text,uuid,text,uuid) from public;
revoke all on function public.rate_hypothesis(text,uuid,text,uuid,smallint,smallint) from public;

grant execute on function public.join_workshop(text,text) to anon, authenticated;
grant execute on function public.get_board(text) to anon, authenticated;
grant execute on function public.add_hypothesis(text,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.delete_hypothesis(text,uuid,text,uuid) to anon, authenticated;
grant execute on function public.rate_hypothesis(text,uuid,text,uuid,smallint,smallint) to anon, authenticated;
