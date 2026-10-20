-- 0004: eier og frist
--
-- «Må avklares» skal kunne leses som en oppgaveliste styringsgruppen kan beslutte
-- på. En linje uten navn og dato er en bekymring, ikke en oppgave.
--
-- eier er fritekst og tåler flere navn («Gruppe 1 + KraftCERT»). Vi normaliserer
-- ikke mot en personliste: i et forprosjekt er eieren like ofte en gruppe eller en
-- ekstern part som en navngitt person.
--
-- frist tas imot som tekst, ikke date, for å kunne skille to tilfeller fra
-- hverandre i update: null betyr «ikke rør feltet», tom streng betyr «fjern
-- fristen». Med en date-parameter hadde de to vært umulige å skille.

alter table public.hypotheses
  add column if not exists eier text not null default ''
  check (char_length(eier) <= 200);

alter table public.hypotheses
  add column if not exists frist date;

-- Tolker '' som null, validerer formatet, og gir en lesbar feil i stedet for
-- Postgres' egen castfeil.
create or replace function private.parse_frist(p text)
returns date language plpgsql immutable set search_path = '' as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  if btrim(p) !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Fristen må være på formen ÅÅÅÅ-MM-DD' using errcode = '22007';
  end if;
  return btrim(p)::date;
end $$;

revoke all on function private.parse_frist(text) from public, anon, authenticated;

-- ---------- get_board: ta med eier og frist ----------
create or replace function public.get_board(p_code text)
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

-- ---------- add_hypothesis ----------
drop function if exists public.add_hypothesis(text,uuid,text,text,text,text,text);

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

-- ---------- update_hypothesis ----------
drop function if exists public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text);

create function public.update_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null,
  p_status text default null, p_kilde text default null,
  p_eier text default null, p_frist text default null)
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
    kilde     = coalesce(left(btrim(p_kilde), 300), kilde),
    eier      = coalesce(left(btrim(p_eier), 200), eier),
    -- null = ikke rør, '' = fjern fristen
    frist     = case when p_frist is null then frist else private.parse_frist(p_frist) end,
    updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

revoke all on function public.add_hypothesis(text,uuid,text,text,text,text,text,text,text) from public;
revoke all on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text) from public;
grant execute on function public.add_hypothesis(text,uuid,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text) to anon, authenticated;
