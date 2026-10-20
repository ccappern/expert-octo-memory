-- 0010: automatisk publisering til Confluence
--
-- Hypotesene og tallene skal stå på Confluence-siden «Hypoteser», slik at
-- styringsgruppen leser dem der de leser alt annet — uten at noen må huske å
-- eksportere. Samme mønster som confluence-sync i nettside-prosjektet:
--
--   private.confluence          hemmelighet, innholdssum og sperre mot for hyppige kall
--   public.confluence_sync_secret()    edge-funksjonen autentiserer seg med denne
--   public.confluence_sync_changed()   skriver bare når innholdet faktisk er endret
--   private.notify_confluence_sync()   trigger på hypoteser og vurderinger
--   cron-jobben confluence-sync-5min   fanger opp det triggeren måtte bomme på
--
-- Hemmeligheten genereres her og forlater aldri databasen annet enn til
-- edge-funksjonen, som kjører med service-nøkkelen. Begge RPC-ene er derfor
-- tilgjengelige for service_role og ingen andre — anon må ikke kunne lese den.
--
-- Triggeren er på setningsnivå, ikke radnivå: et innlegg som endrer ti rader
-- skal gi ett kall, ikke ti. I tillegg sperres det for mer enn ett kall i
-- minuttet, slik at en workshop der seksten personer vurderer samtidig ikke
-- hamrer på Confluence-API-et.

create extension if not exists pg_net;
create extension if not exists pg_cron;

create table if not exists private.confluence (
  id            boolean primary key default true check (id),
  hemmelighet   text not null default encode(extensions.gen_random_bytes(32), 'hex'),
  funksjon_url  text not null default 'https://ryzeahdqxtclliyhdlki.supabase.co/functions/v1/confluence-sync',
  hash          text not null default '',
  sist_varslet  timestamptz,
  oppdatert     timestamptz
);
insert into private.confluence (id) values (true) on conflict (id) do nothing;

-- ---------- RPC-er som edge-funksjonen bruker ----------
create or replace function public.confluence_sync_secret()
returns text language sql stable security definer set search_path = '' as $$
  select hemmelighet from private.confluence where id;
$$;

-- Returnerer true bare når summen er ny, og lagrer den i samme operasjon. At
-- lesing og skriving skjer i én setning er poenget: to samtidige kjøringer kan
-- da ikke begge få true og skrive hver sin versjon til Confluence.
create or replace function public.confluence_sync_changed(new_hash text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_endret boolean;
begin
  update private.confluence
     set hash = new_hash, oppdatert = now()
   where id and hash is distinct from new_hash
  returning true into v_endret;
  return coalesce(v_endret, false);
end $$;

revoke all on function public.confluence_sync_secret() from public, anon, authenticated;
revoke all on function public.confluence_sync_changed(text) from public, anon, authenticated;
grant execute on function public.confluence_sync_secret() to service_role;
grant execute on function public.confluence_sync_changed(text) to service_role;

-- ---------- kallet ----------
-- Brukes av både triggeren og cron-jobben. Sperren på ett minutt gjelder bare
-- triggeren; cron kaller uansett, fordi den er det som fanger opp en endring
-- som kom rett etter forrige kall.
create or replace function private.confluence_kall(p_respekter_sperre boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
declare v_url text; v_hem text; v_sist timestamptz;
begin
  select funksjon_url, hemmelighet, sist_varslet
    into v_url, v_hem, v_sist
    from private.confluence where id;
  if v_url is null or v_hem is null then return; end if;
  if p_respekter_sperre and v_sist is not null and v_sist > now() - interval '1 minute' then
    return;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_hem),
    body    := '{}'::jsonb,
    timeout_milliseconds := 8000);

  update private.confluence set sist_varslet = now() where id;
end $$;

revoke all on function private.confluence_kall(boolean) from public, anon, authenticated;

create or replace function private.notify_confluence_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Feil her skal aldri velte skrivingen deltakeren holder på med. En tapt
  -- varsling tas uansett av cron-jobben fem minutter senere.
  begin
    perform private.confluence_kall(true);
  exception when others then
    raise warning 'confluence-varsling feilet: %', sqlerrm;
  end;
  return null;
end $$;

-- ---------- triggere ----------
drop trigger if exists hypoteser_confluence on public.hypotheses;
create trigger hypoteser_confluence
  after insert or update or delete on public.hypotheses
  for each statement execute function private.notify_confluence_sync();

drop trigger if exists vurderinger_confluence on public.ratings;
create trigger vurderinger_confluence
  after insert or update or delete on public.ratings
  for each statement execute function private.notify_confluence_sync();

-- ---------- cron ----------
do $$
begin
  perform cron.unschedule('confluence-sync-5min');
exception when others then null;   -- jobben fantes ikke
end $$;

select cron.schedule('confluence-sync-5min', '*/5 * * * *',
  $$select private.confluence_kall(false)$$);
