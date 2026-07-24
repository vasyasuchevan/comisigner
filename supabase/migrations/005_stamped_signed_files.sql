-- ComiSigner — migrația 005: fișier "ștampilat" (semnătura desenată, compusă
-- vizual peste documentul original) pentru fiecare semnare
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile
-- anterioare.
--
-- De ce: până acum semnătura era stocată DOAR separat (bucket "signatures"),
-- niciodată "arsă" peste documentul original — corect din punct de vedere al
-- verificării hash-ului (hash-ul se calculează mereu pe fișierul ORIGINAL,
-- nemodificat, ca să detecteze orice manipulare), dar vizual nesatisfăcător:
-- VSL a cerut explicit să vadă documentul cu semnătura aplicată pe el, nu
-- doar o poză separată a semnăturii lângă niște metadate.
--
-- Soluție: la semnare, clientul (driver/) generează ACUM o a doua copie a
-- documentului, cu imaginea semnăturii desenată peste el (pdf-lib pentru
-- PDF, <canvas> pentru imagini), și o încarcă separat. Hash-ul de audit
-- NU SE ATINGE — continuă să fie calculat exact ca înainte, pe bytes-ii
-- documentului original re-descărcat, înainte de orice compunere vizuală.
-- Copia ștampilată e doar pentru afișare/download în /office/, nu participă
-- deloc la lanțul de audit sau la verificarea de integritate.

-- 1) bucket nou, public (la fel ca "documents") — fișierele ștampilate se
--    citesc direct prin URL public, fără autentificare, din /office/.
insert into storage.buckets (id, name, public)
values ('signed_files', 'signed_files', true)
on conflict (id) do nothing;

-- 2) șoferul (rol anonim) trebuie să poată încărca fișierul ștampilat chiar
--    după ce a semnat — la fel cum poate încărca deja în bucket-ul
--    "signatures". Fără citire/ștergere pentru anonim; citirea publică vine
--    din faptul că bucket-ul e public (la fel ca la "documents"), nu dintr-o
--    politică separată.
drop policy if exists "signed_files_insert_anyone" on storage.objects;
create policy "signed_files_insert_anyone" on storage.objects
  for insert
  to anon, authenticated
  with check (bucket_id = 'signed_files');

-- 3) coloană nouă — calea către fișierul ștampilat, NULL dacă generarea a
--    eșuat (nu trebuie să blocheze niciodată semnarea propriu-zisă) sau
--    pentru înregistrări mai vechi, dinainte de această migrație.
alter table public.signed_documents
  add column if not exists stamped_file_path text;
