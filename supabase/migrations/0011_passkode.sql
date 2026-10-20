-- 0011: «passkode» i stedet for «workshopkode»
--
-- Innloggingsskjemaet kaller feltet Passkode. Feilmeldingen fra databasen sa
-- «Ugyldig workshopkode», og den teksten vises direkte til deltakeren — både
-- ved innlogging og hvis koden byttes mens noen er inne. To navn på samme ting
-- i samme grensesnitt er en unødvendig grunn til å lure.
--
-- Bare teksten endres. Feilkoden 28000 er uendret, og klienten skiller fortsatt
-- på den og ikke på ordlyden.

create or replace function private.workshop_by_code(p_code text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid;
begin
  select w.id into v_id from public.workshops w
   where w.code_hash = extensions.crypt(upper(btrim(coalesce(p_code,''))), w.code_hash)
   limit 1;
  if v_id is null then
    raise exception 'Ugyldig passkode' using errcode = '28000';
  end if;
  return v_id;
end $$;

revoke all on function private.workshop_by_code(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
