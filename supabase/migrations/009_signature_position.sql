-- ComiSigner — migrația 009: poziție manuală/prestabilită a semnăturii
--
-- Rulați integral în Supabase Dashboard → SQL Editor, la fel ca migrațiile anterioare.
--
-- De ce: detectarea automată a locului semnăturii (OCR) e o euristică — nu nimerește
-- mereu locul corect, iar când nu găsește nimic, șoferul nu avea până acum NICIO
-- modalitate de a indica manual unde trebuie semnat (semnătura se punea automat în
-- colțul din dreapta jos al ultimei pagini). Acest câmp permite fie biroul să
-- pre-seteze locul la încărcare (opțional, doar pentru un singur PDF), fie șoferul
-- să atingă documentul pentru a pune/muta punctul — vezi driver/index.html și
-- office/index.html. Coordonatele sunt procentuale (0-100, colț stânga-sus), ca să nu
-- depindă de rezoluția/scala la care fiecare parte randează documentul.

alter table public.documents
  add column if not exists signature_page int,
  add column if not exists signature_x_pct numeric,
  add column if not exists signature_y_pct numeric;

-- get_document_by_id trebuie să întoarcă și aceste câmpuri către șofer (anonim) —
-- se înlocuiește funcția din migrația 002, adăugând doar cele trei coloane noi.

drop function if exists public.get_document_by_id(uuid);

create or replace function public.get_document_by_id(p_id uuid)
returns table (
  id uuid,
  document_id text,
  title text,
  doc_type text,
  doc_date text,
  file_path text,
  file_type text,
  status text,
  driver_full_name text,
  is_expired boolean,
  signature_page int,
  signature_x_pct numeric,
  signature_y_pct numeric
)
language sql
security definer
set search_path = public
as $$
  select
    d.id,
    d.document_id,
    d.title,
    d.doc_type,
    d.doc_date::text,
    d.file_path,
    d.file_type,
    d.status,
    dr.full_name as driver_full_name,
    (d.expires_at is not null and now() > d.expires_at and d.status = 'pending') as is_expired,
    d.signature_page,
    d.signature_x_pct,
    d.signature_y_pct
  from public.documents d
  left join public.drivers dr on dr.id = d.driver_id
  where d.id = p_id;
$$;

grant execute on function public.get_document_by_id(uuid) to anon, authenticated;
