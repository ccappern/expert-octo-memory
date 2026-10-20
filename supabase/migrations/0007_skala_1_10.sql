-- 0007: skala 1–10 i stedet for 1–5
--
-- 1–5 har et midtpunkt, og 3 blir et gjemmested for den som er usikker. 1–10 har
-- ikke noe midtpunkt — 5,5 finnes ikke som valg — så hver deltaker må velge side.
-- Finere oppløsning gir også en reell rangering i «Må avklares», der 1–5 gjerne
-- ga ti hypoteser med samme score.
--
-- Grensen mellom kvadrantene går nå ved 5,5 og ikke ved 3. Terskelen for at
-- vurderingene spriker er hevet tilsvarende, fra 3 av 4 mulige trinn til 6 av 9.
--
-- Eventuelle eksisterende vurderinger regnes om med (v-1)*9/4+1, altså
-- 1→1, 2→3, 3→6, 4→8, 5→10. Omregningen kjøres nøyaktig én gang; markøren i
-- private.meta hindrer at en ny kjøring skalerer tallene en gang til.

create table if not exists private.meta (
  key   text primary key,
  value text not null,
  satt  timestamptz not null default now()
);
revoke all on private.meta from public, anon, authenticated;

alter table public.ratings drop constraint if exists ratings_k_check;
alter table public.ratings drop constraint if exists ratings_u_check;

do $$
declare v_n int;
begin
  if exists (select 1 from private.meta where key = 'skala' and value = '10') then
    raise notice 'Skalaen er allerede 1-10. Hopper over omregningen.';
  else
    update public.ratings
       set k = case when k is null then null else round((k - 1) * 9.0 / 4.0) + 1 end,
           u = case when u is null then null else round((u - 1) * 9.0 / 4.0) + 1 end,
           updated_at = now();
    get diagnostics v_n = row_count;
    insert into private.meta (key, value) values ('skala', '10')
      on conflict (key) do update set value = '10', satt = now();
    raise notice 'Regnet om % vurderinger fra 1-5 til 1-10.', v_n;
  end if;
end $$;

alter table public.ratings add constraint ratings_k_check check (k between 1 and 10);
alter table public.ratings add constraint ratings_u_check check (u between 1 and 10);
