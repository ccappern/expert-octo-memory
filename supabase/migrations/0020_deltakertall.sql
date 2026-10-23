-- 0020: hvor mange som KAN svare, ikke bare hvor mange som har gjort det.
--
-- «1 deltakere har vurdert» sier ingenting. Er det 1 av 3 eller 1 av 21? Det
-- første er en god start, det andre er et problem. Uten nevneren må leseren
-- gjette, og da gjetter folk i den retningen som passer dem best.
--
-- Telles på e-post og ikke på rader: «Forprosjektdokumentasjonen» eier 27
-- hypoteser, men er ikke en person og kan aldri logge inn. Tas den med, får
-- rommet en nevner som aldri kan nås.

drop function if exists public.get_board();

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
    'deltakere_totalt', (select count(*) from public.participants
                          where workshop_id = v_ws and epost is not null),
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

    'tellinger', coalesce((
      select json_agg(json_build_object(
        'h', h.id,
        'n', (select count(*) from public.ratings r
               where r.hypothesis_id = h.id and r.k >= 1 and r.u >= 1),
        'vetIkke', (select count(*) from public.ratings r
                     where r.hypothesis_id = h.id and (r.k = 0 or r.u = 0))))
      from public.hypotheses h
      where h.workshop_id = v_ws and h.deleted_at is null), '[]'::json),

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
        )), '[]'::json),

    -- Hvor mange som har avgitt minst én vurdering. Hentes her og ikke i
    -- klienten, fordi klienten i lukket modus bare ser sine egne rader og
    -- dermed alltid ville talt én.
    'deltakere_vurdert', (
      select count(distinct r.participant_id)
        from public.ratings r join public.hypotheses h on h.id = r.hypothesis_id
       where h.workshop_id = v_ws and h.deleted_at is null)
  );
end $$;

revoke all on function public.get_board() from public, anon;
grant execute on function public.get_board() to authenticated;

notify pgrst, 'reload schema';
