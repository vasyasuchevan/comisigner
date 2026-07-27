-- ComiSigner — migrația 010: ștergere șofer (dacă e "gol") + reglare ulterioară
-- a semnăturii vizuale pe un document deja semnat
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile anterioare.

-- ============================================================================
-- 1) Ștergere șofer — doar Admin, doar dacă șoferul nu are NICIUN document și
--    NICIUN link de dosar generat.
-- ============================================================================
-- De ce blocăm în loc să ștergem în cascadă: un document semnat nu poate fi
-- pierdut niciodată (e registrul de audit) — deci un șofer cu istoric rămâne
-- definitiv nu-ștergibil prin acest drum. E gândit ca curățare pentru șoferi
-- adăugați din greșeală, nu ca "ștergere completă a unui șofer real".

drop policy if exists "drivers_delete_admin_if_empty" on public.drivers;
create policy "drivers_delete_admin_if_empty" on public.drivers
  for delete
  to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    and not exists (select 1 from public.documents d where d.driver_id = drivers.id)
    and not exists (select 1 from public.dossier_links l where l.driver_id = drivers.id)
  );

-- ============================================================================
-- 2) Reglare ulterioară a copiei "ștampilate" (poziție/mărime/transparență a
--    semnăturii desenate peste document) — doar Admin, doar câmpul
--    stamped_file_path.
-- ============================================================================
-- signed_documents e conceput ca registru append-only — până acum nicio
-- politică de update/delete pentru niciun rol. stamped_file_path e strict
-- cosmetic (nu participă la hash/lanțul de audit, vezi migrația 005), deci e
-- singurul câmp unde o corecție ulterioară nu pune deloc în pericol dovada.
-- O politică RLS nu poate restrânge la o singură coloană (verifică rânduri,
-- nu coloane) — de-asta e nevoie și de un trigger care blochează explicit
-- orice încercare de a schimba altceva.

drop policy if exists "signed_documents_update_admin_stamped_file" on public.signed_documents;
create policy "signed_documents_update_admin_stamped_file" on public.signed_documents
  for update
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create or replace function public.prevent_signed_documents_tamper()
returns trigger
language plpgsql
as $$
begin
  if new.document_id is distinct from old.document_id
     or new.driver_name is distinct from old.driver_name
     or new.device_id is distinct from old.device_id
     or new.hash is distinct from old.hash
     or new.signed_at is distinct from old.signed_at
     or new.document_ref is distinct from old.document_ref
     or new.document_content is distinct from old.document_content
     or new.signature_path is distinct from old.signature_path
     or new.seq is distinct from old.seq
     or new.prev_chain_hash is distinct from old.prev_chain_hash
     or new.chain_hash is distinct from old.chain_hash
  then
    raise exception 'signed_documents este un registru de audit imuabil — doar stamped_file_path poate fi actualizat.';
  end if;
  return new;
end;
$$;

drop trigger if exists signed_documents_only_stamped_file_path on public.signed_documents;
create trigger signed_documents_only_stamped_file_path
  before update on public.signed_documents
  for each row
  execute function public.prevent_signed_documents_tamper();

-- Notă: bucket-ul "signed_files" permite deja upload pentru "authenticated"
-- (nu doar "anon"), din migrația 005 — nu e nevoie de o politică nouă de
-- storage pentru ca un Admin să încarce o copie ștampilată reglată din nou.
