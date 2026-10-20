-- 0002: kilde på hypotesene
--
-- Hypotesene som er hentet fra forprosjektdokumentasjonen skal kunne spores
-- tilbake til dokumentet de stammer fra. Uten dette feltet blir de påstander
-- uten forankring, og da er de verdiløse i en diskusjon.
--
-- Feltet er valgfritt: hypoteser deltakerne finner på i workshopen har normalt
-- ingen kilde ennå.
--
-- RPC-ene får p_kilde med default, slik at en klient som ennå ikke er oppdatert
-- fortsetter å virke. Rekkefølgen SQL-først, deretter publisering, er derfor
-- trygg.

alter table public.hypotheses
  add column if not exists kilde text not null default ''
  check (char_length(kilde) <= 300);

-- ---------- get_board: ta med kilde ----------
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
        'kilde', h.kilde,
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

-- ---------- add_hypothesis: ny signatur med p_kilde ----------
drop function if exists public.add_hypothesis(text,uuid,text,text,text,text);

create function public.add_hypothesis(p_code text, p_pid uuid, p_token text,
  p_tekst text, p_kriterium text, p_type text, p_kilde text default '')
returns json language plpgsql volatile security definer set search_path = '' as $$
declare v_ws uuid; v_nr int; v_id uuid;
begin
  v_ws := private.workshop_by_code(p_code);
  perform private.participant_ok(v_ws, p_pid, p_token);
  perform 1 from public.workshops where id = v_ws for update;  -- serialiserer nummerering
  select coalesce(max(nr), 0) + 1 into v_nr from public.hypotheses where workshop_id = v_ws;
  insert into public.hypotheses (workshop_id, nr, tekst, kriterium, type, kilde, created_by)
  values (v_ws, v_nr, btrim(p_tekst), coalesce(btrim(p_kriterium), ''), p_type,
          left(coalesce(btrim(p_kilde), ''), 300), p_pid)
  returning id into v_id;
  return json_build_object('id', v_id, 'nr', v_nr);
end $$;

-- ---------- update_hypothesis: ny signatur med p_kilde ----------
drop function if exists public.update_hypothesis(text,uuid,text,uuid,text,text,text,text);

create function public.update_hypothesis(p_code text, p_pid uuid, p_token text, p_id uuid,
  p_tekst text default null, p_kriterium text default null, p_type text default null,
  p_status text default null, p_kilde text default null)
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
    updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

revoke all on function public.add_hypothesis(text,uuid,text,text,text,text,text) from public;
revoke all on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text) from public;
grant execute on function public.add_hypothesis(text,uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text) to anon, authenticated;
