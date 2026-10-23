-- 0018: resultatvisning — tre moduser, håndhevet i databasen.
--
-- Problemet: «Gruppens snitt vises ikke i Min vurdering» sto som domeneregel,
-- men var bare implementert i matrisen. På hypotesekortet lå snittet rett under
-- de to skalaene du skulle klikke på, og i detaljpanelet sto det igjen. Den som
-- vurderte, så altså hvor flertallet lå i samme øyeblikk som valget ble tatt.
--
-- Hvorfor sperren ligger her og ikke i klienten: den publiserbare nøkkelen står
-- i config.js og er ment å være kjent. Lar get_board alle vurderingene passere
-- og bare lar klienten være å tegne dem, er sperren kosmetikk — hvem som helst
-- med konsollen åpen kan kalle RPC-en og lese tallene. Derfor filtreres radene
-- før de forlater databasen.
--
-- Tre moduser:
--   lukket        bare dine egne vurderinger sendes ut
--   etter_stemme  andres sendes først for hypoteser du selv har vurdert
--   apent         alt, som før
--
-- Antallet er med i alle tre. «3 har vurdert» anker ingen retning, men sier om
-- hypotesen er moden for diskusjon. Derfor beregnes tellingene for seg og
-- sendes alltid, uavhengig av hvilke rader som slippes gjennom.

alter table public.workshops add column if not exists resultatvisning text not null default 'etter_stemme';
alter table public.workshops drop constraint if exists workshops_resultatvisning_check;
alter table public.workshops add  constraint workshops_resultatvisning_check
  check (resultatvisning in ('lukket','etter_stemme','apent'));

do $$
declare r record; v_n int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('get_board','admin_sett_resultatvisning')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
    v_n := v_n + 1;
  end loop;
  raise notice 'Fjernet % funksjonsutgaver.', v_n;
end $$;

create function public.get_board()
returns json language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_ws uuid; v_modus text;
begin
  select m.v_pid, m.v_ws into v_pid, v_ws from private.meg() m;
  select resultatvisning into v_modus from public.workshops where id = v_ws;

  return json_build_object(
    'workshop', (select name from public.workshops where id = v_ws),
    'meg', v_pid,
    'admin', coalesce((select admin from public.participants where id = v_pid), false),
    'resultatvisning', v_modus,
    'leveranser', coalesce((
      select json_agg(json_build_object(
        'slug', d.slug, 'nr', d.nr, 'label', d.label,
        'hint', d.hint, 'valgbar', d.valgbar) order by d.nr, d.label)
      from public.deliverables d where d.workshop_id = v_ws), '[]'::json),
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

    -- Egne vurderinger slipper alltid gjennom: du skal kunne se hva du selv
    -- har svart, uansett modus.
    'ratings', coalesce((
      select json_agg(json_build_object('h', r.hypothesis_id, 'p', r.participant_id, 'k', r.k, 'u', r.u))
      from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
      where h.workshop_id = v_ws and h.deleted_at is null
        and (
          v_modus = 'apent'
          or r.participant_id = v_pid
          or (v_modus = 'etter_stemme' and exists (
                select 1 from public.ratings meg
                 where meg.hypothesis_id = r.hypothesis_id
                   and meg.participant_id = v_pid
                   and meg.k is not null and meg.u is not null))
        )), '[]'::json)
  );
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

revoke all on function public.get_board() from public, anon;
revoke all on function public.admin_sett_resultatvisning(text) from public, anon;
grant execute on function public.get_board() to authenticated;
grant execute on function public.admin_sett_resultatvisning(text) to authenticated;

notify pgrst, 'reload schema';
