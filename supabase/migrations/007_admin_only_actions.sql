-- ComiSigner — migrația 007: ștergere/înlocuire document și acces la /api/staff — doar Admin
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile anterioare.
--
-- De ce: până acum Admin și HR aveau exact aceleași drepturi în baza de date — rolul
-- era doar o etichetă afișată în interfață. Șoferul HR poate acum doar să adauge
-- șoferi/documente/linkuri (ca înainte); ștergerea unui document, înlocuirea fișierului
-- lui, și noul panou "Echipă" (adăugare/dezactivare colegi) devin exclusiv pentru Admin.
-- Politicile de mai jos înlocuiesc exact aceleași politici din migrațiile 003 și 006,
-- adăugând condiția "p.role = 'admin'" pe lângă verificarea deja existentă că
-- utilizatorul are un rând în profiles.

drop policy if exists "documents_delete_staff_pending" on public.documents;
create policy "documents_delete_staff_pending" on public.documents
  for delete
  to authenticated
  using (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

drop policy if exists "documents_bucket_delete_staff" on storage.objects;
create policy "documents_bucket_delete_staff" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'documents'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

drop policy if exists "documents_update_staff_pending" on public.documents;
create policy "documents_update_staff_pending" on public.documents
  for update
  to authenticated
  using (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  )
  with check (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Notă: "Verifică lanțul complet" (verificarea integrală a lanțului de audit) rămâne
-- doar o citire (select pe signed_documents, deja permisă oricărui membru al echipei) —
-- nu există nimic de restricționat la nivel de bază de date acolo. Ascunderea butonului
-- pentru HR se face doar în interfață (office/index.html), ca o comoditate, nu ca o
-- graniță de securitate.
--
-- Notă despre panoul "Echipă": crearea/dezactivarea conturilor de birou nu trece prin
-- RLS deloc — se face prin funcția serverless api/staff.js, care folosește service_role
-- key și verifică ea însăși, la fiecare cerere, că apelantul are role = 'admin' în
-- profiles înainte de a face orice. Nu e nevoie de o politică RLS suplimentară aici.
