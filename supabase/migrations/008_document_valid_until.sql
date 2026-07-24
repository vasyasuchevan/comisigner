-- ComiSigner — migrația 008: „Valabil până la" (data expirării reale a documentului)
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile anterioare.
--
-- De ce: aplicația urmărea până acum doar expirarea linkului de semnare (24h) — nu
-- și data reală de expirare a documentului în sine (ex: permisul sau certificatul
-- medical al șoferului). Câmpul e complet opțional și nu participă niciodată la
-- hash-ul de audit — e metadata operațională, nu parte din dovada de semnare.

alter table public.documents
  add column if not exists valid_until date;

-- HR poate seta "valid_until" încă de la încărcare — INSERT-ul e deja permis fără
-- restricții pe coloane (migrația 002), deci nu e nevoie de nimic nou pentru asta.
-- Ce lipsește e dreptul de a-l MODIFICA pe un document deja existent (inclusiv unul
-- deja semnat) — asta rămâne exclusiv Admin, la fel ca ștergerea/înlocuirea fișierului
-- (migrația 007). Nu slăbește nimic pentru HR — HR tot nu poate actualiza documente
-- existente; doar extinde ce poate face Admin (deja pe deplin încrezut) și la
-- documentele semnate, nu doar la cele „pending".

drop policy if exists "documents_update_admin_valid_until" on public.documents;
create policy "documents_update_admin_valid_until" on public.documents
  for update
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
