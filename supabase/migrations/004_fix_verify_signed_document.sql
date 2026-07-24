-- ComiSigner — migrația 004: repară verify_signed_document (rupt de migrația 002)
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrația 002/003.
--
-- Bug: migrația 002 a redenumit documents.route -> documents.doc_type, dar
-- funcția verify_signed_document (creată înainte să existe folderul de
-- migrații, direct din SQL Editor) nu a fost actualizată — a rămas cu o
-- referință la coloana veche "route", care nu mai există. Rezultat: pagina
-- publică /verify/ (singurul loc din aplicație care cheamă această funcție)
-- eșua mereu cu "column d.route does not exist". Panoul /office/ nu era
-- afectat — el recalculează lanțul direct din tabele, fără RPC.
--
-- p_id aici e id-ul din signed_documents (evenimentul de semnare), nu din
-- documents — /verify/?id=... trimite mereu signed_documents.id.

drop function if exists public.verify_signed_document(uuid);

create or replace function public.verify_signed_document(p_id uuid)
returns table (
  driver_name text,
  doc_title text,
  doc_type text,
  doc_date text,
  signed_at text,
  hash text,
  prev_chain_hash text,
  chain_hash text,
  seq bigint
)
language sql
security definer
set search_path = public
as $$
  select
    sd.driver_name,
    d.title as doc_title,
    d.doc_type,
    d.doc_date::text,
    sd.signed_at::text,
    sd.hash,
    sd.prev_chain_hash,
    sd.chain_hash,
    sd.seq
  from public.signed_documents sd
  left join public.documents d on d.id = sd.document_ref
  where sd.id = p_id;
$$;

grant execute on function public.verify_signed_document(uuid) to anon, authenticated;
