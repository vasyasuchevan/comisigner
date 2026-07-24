-- ComiSigner — migrația 006: permite înlocuirea fișierului unui document nesemnat
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile anterioare.
--
-- De ce: HR poate încărca din greșeală fișierul greșit. Până acum singura opțiune era
-- să șteargă documentul și să încarce unul nou — dar asta rupe linkul deja trimis
-- șoferului (migrația 003). "Înlocuiește fișierul" actualizează file_path/file_type/
-- file_hash pe ACELAȘI rând din documents, păstrând id-ul (deci și linkul/codul QR)
-- neschimbat. Ca și la ștergere, permis DOAR pentru documente cu status = 'pending' —
-- un document deja semnat nu poate fi modificat niciodată (ar rupe lanțul de audit).
--
-- Nu e nevoie de o politică nouă de storage — bucket-ul "documents" are deja upload
-- pentru staff (folosit la încărcarea inițială) și delete pentru staff (migrația 003,
-- folosit aici ca să curețe fișierul vechi, înlocuit).

drop policy if exists "documents_update_staff_pending" on public.documents;
create policy "documents_update_staff_pending" on public.documents
  for update
  to authenticated
  using (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid())
  )
  with check (
    status = 'pending'
    and exists (select 1 from public.profiles p where p.id = auth.uid())
  );
