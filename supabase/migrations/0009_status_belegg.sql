-- 0009: belegg for statusendringer, og avklart status som flytter hypotesen
--
-- To ting henger sammen her.
--
-- 1) «Bekreftet» og «Avkreftet» betyr at usikkerheten er borte: vi testet, og nå
--    vet vi. Klienten regner derfor usikkerheten som 1 for disse, slik at en
--    bekreftet kritisk hypotese havner i «Grunnlag» — premisset anbefalingen
--    hviler på — i stedet for å bli stående i «Må avklares» for alltid.
--    Kritikaliteten røres ikke: en bekreftet kritisk antakelse er fortsatt
--    kritisk, det er nettopp derfor den er et premiss.
--
-- 2) Når en statusendring flytter en hypotese inn i grunnlaget for anbefalingen,
--    må det kunne spores hva som avgjorde det. Uten belegg er «Bekreftet» bare
--    en påstand til, og da er vi tilbake til der registeret skulle hjelpe oss ut.
--    Derfor kreves status_notat ved bekreftet og avkreftet. Kravet håndheves her
--    og ikke bare i nettleseren, slik at det gjelder uansett klient.
--
-- status_endret og status_av settes av serveren, ikke av klienten: hvem som
-- avklarte hva og når er en revisjonsopplysning, ikke et skjemafelt.
--
-- Eksisterende rader beholder status og får tomt notat. Kravet gjelder bare ved
-- nye endringer, så migrasjonen bryter ikke historikken.

alter table public.hypotheses
  add column if not exists status_notat text not null default ''
  check (char_length(status_notat) <= 500);

alter table public.hypotheses
  add column if not exists status_endret timestamptz;

alter table public.hypotheses
  add column if not exists status_av uuid references public.participants(id);

-- ---------- get_board: ta med belegget ----------
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

-- ---------- update_hypothesis: p_status_notat ----------
drop function if exists public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text);

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

  -- Belegg kreves bare når statusen faktisk settes til avklart. Retting av
  -- tekst eller eier på en allerede bekreftet hypotese skal ikke kreve det på
  -- nytt, ellers blir feltet et hinder i stedet for en opplysning.
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
    -- null = ikke rør, '' = fjern fristen
    frist     = case when p_frist is null then frist else private.parse_frist(p_frist) end,
    -- Notatet hører til statusen og nullstilles når den endres uten nytt belegg,
    -- slik at et gammelt notat ikke blir stående som begrunnelse for en ny status.
    status_notat  = case when v_endret then v_notat
                         when p_status_notat is null then status_notat
                         else v_notat end,
    status_endret = case when v_endret then now() else status_endret end,
    status_av     = case when v_endret then p_pid else status_av end,
    updated_at = now()
  where id = p_id and workshop_id = v_ws and deleted_at is null;
end $$;

revoke all on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text,text) from public;
grant execute on function public.update_hypothesis(text,uuid,text,uuid,text,text,text,text,text,text,text,text) to anon, authenticated;

-- ---------- be PostgREST lese skjemaet på nytt ----------
-- Uten dette svarer API-et «Could not find the function ... in the schema cache»
-- på den nye signaturen, selv om funksjonen står i databasen.
notify pgrst, 'reload schema';
