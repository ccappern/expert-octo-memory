-- 0019: Confluence skal ikke skrives hvert minutt mens folk stemmer.
--
-- Triggeren sto på både `hypotheses` og `ratings`. Den på vurderingene var den
-- dyre: seksten personer som vurderer tjueåtte hypoteser i en time utløser
-- minuttsperren omtrent seksti ganger, og hver gang skrives hele siden på nytt
-- hos Atlassian. Innholdet endrer seg marginalt mellom hver skriving — et snitt
-- som flytter seg fra 7,8 til 7,9 — så kostnaden står ikke i forhold til nytten.
--
-- Hypotesene beholder sin trigger. Der er endringene reelle og sjeldne: ny
-- hypotese, endret status, nytt belegg, ny eier. Det er verdt å publisere med
-- en gang.
--
-- Vurderingene fanges i stedet av cron, som flyttes fra fem til femten minutter.
-- Styringsgruppen trenger et ferskt bilde, ikke et sanntidsbilde — og under en
-- workshop er tallene uansett i bevegelse helt til runden er over.

drop trigger if exists vurderinger_confluence on public.ratings;

do $$
begin
  perform cron.unschedule('confluence-sync-5min');
exception when others then null;   -- jobben fantes ikke
end $$;

do $$
begin
  perform cron.unschedule('confluence-sync-15min');
exception when others then null;
end $$;

select cron.schedule('confluence-sync-15min', '*/15 * * * *',
  $$select private.confluence_kall(false)$$);
