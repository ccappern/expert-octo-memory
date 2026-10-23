-- «Vet ikke» som eget svar på hver akse.
--
-- Hvorfor: skalaen 1–10 kunne bare skille mellom «jeg mener usikkerheten er lav»
-- og ingenting. Den som ikke hadde grunnlag for å mene noe, måtte enten gjette
-- eller la være å svare — og begge deler ser like ut i snittet. At mange ikke
-- kan svare på en hypotese er i seg selv et funn: ingen i rommet vet.
--
-- Hvordan: 0 er sentinelverdien for «vet ikke». Den er utenfor skalaen, så den
-- kan ikke forveksles med en vurdering, og den holdes utenfor snittet i
-- klienten. NULL betyr fortsatt «har ikke svart på denne aksen», og en rad som
-- er NULL på begge slettes som før av rate_hypothesis.
--
-- Merk at rate_hypothesis ikke trenger endring: den sletter allerede bare når
-- begge er NULL, og skriver verdiene rått. Det er CHECK-en som stengte 0 ute.

alter table public.ratings drop constraint if exists ratings_k_check;
alter table public.ratings drop constraint if exists ratings_u_check;
alter table public.ratings add constraint ratings_k_check check (k between 0 and 10);
alter table public.ratings add constraint ratings_u_check check (u between 0 and 10);

notify pgrst, 'reload schema';
