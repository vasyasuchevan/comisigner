-- ComiSigner — migrația 003: permite ștergerea unui document nesemnat
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrația 002.
--
-- De ce: HR poate încărca din greșeală fișierul greșit pentru un șofer.
-- Ștergerea e permisă DOAR pentru documente cu status = 'pending' — un
-- document deja semnat nu poate fi șters niciodată din UI, ca să nu se
-- rupă lanțul de audit (signed_documents.document_ref ar rămâne agățat de
-- un document inexistent). Politica de mai jos aplică exact aceeași regulă
-- la nivel de bază de date, nu doar în interfață.

drop policy if exists "documents_delete_staff_pending" on public.documents;
create policy "documents_delete_staff_pending" on public.documents
  for delete
  to authenticated
  using (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid())
  );

-- Fișierul din Storage (bucket "documents") trebuie șters separat de rândul
-- din tabel — fără această politică, ștergerea rândului ar reuși dar
-- fișierul PDF ar rămâne orfan în Storage la nesfârșit.

drop policy if exists "documents_bucket_delete_staff" on storage.objects;
create policy "documents_bucket_delete_staff" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'documents'
    and exists (select 1 from public.profiles p where p.id = auth.uid())
  );
