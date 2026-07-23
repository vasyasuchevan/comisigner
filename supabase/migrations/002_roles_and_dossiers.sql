-- ComiSigner — migrația 002: roluri Admin/HR + dosar de documente per șofer
--
-- Rulați acest fișier o singură dată, integral, în Supabase Dashboard → SQL Editor
-- (rulează ca rol "postgres", ocolește RLS — de-asta nu se poate face din aplicație).
-- E scris să poată fi rulat de mai multe ori fără erori (blocuri "if not exists" /
-- verificări explicite), în caz că trebuie reluat după o eroare parțială.

-- ============================================================================
-- 1) profiles — leagă un login din Supabase Auth de un rol (admin sau hr)
-- ============================================================================
-- De ce: astăzi orice login din Auth vede tot panoul /office/, fără nicio
-- distincție de rol. Un rând în "profiles" e ceea ce transformă un login
-- oarecare într-un membru autorizat al echipei — fără rând aici, nu poți
-- adăuga șoferi, documente sau linkuri, chiar dacă ești logat.
-- Rândurile se adaugă manual de voi, din Table Editor, după ce creați
-- utilizatorul în Auth → Users — nu există (și nu va exista) o pagină în
-- aplicație care să creeze conturi, ca să nu fie nevoie de service_role key.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'hr')),
  full_name text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

-- ============================================================================
-- 2) drivers — șoferii care au un dosar de documente
-- ============================================================================
-- Cine poate citi/adăuga șoferi: orice utilizator autentificat care ARE un
-- rând în "profiles" (adică cineva căruia i-ați atribuit rolul admin/hr).
-- Admin și HR au exact aceleași drepturi aici — Alex nu a cerut nicio
-- distincție mai fină între ei, deci nu am inventat una.

create table if not exists public.drivers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

alter table public.drivers enable row level security;

drop policy if exists "drivers_select_staff" on public.drivers;
create policy "drivers_select_staff" on public.drivers
  for select
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid()));

drop policy if exists "drivers_insert_staff" on public.drivers;
create policy "drivers_insert_staff" on public.drivers
  for insert
  to authenticated
  with check (exists (select 1 from public.profiles p where p.id = auth.uid()));

-- ============================================================================
-- 3) documents — adăugăm legătura cu șoferul, redenumim "route" și adăugăm
--    data de expirare a linkului (24h)
-- ============================================================================
-- "route"/"doc_date" erau gândite pentru documente de transport (interpretare
-- greșită, corectată de Alex) — le păstrăm ca și câmpuri (nu pierdem date),
-- doar redenumim "route" în "doc_type" (tip de document: permis, certificat
-- medical etc.) ca să reflecte realitatea.
-- "expires_at" e NULL pentru documentele deja existente în bază (linkuri deja
-- trimise nu se strică brusc), și se completează explicit din aplicație
-- (acum() + 24h) pentru fiecare document nou.

alter table public.documents
  add column if not exists driver_id uuid references public.drivers(id),
  add column if not exists expires_at timestamptz;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'documents' and column_name = 'route'
  ) then
    alter table public.documents rename column route to doc_type;
  end if;
end $$;

-- ============================================================================
-- 4) dossier_links — token-ul din URL pentru "link către tot dosarul"
-- ============================================================================
-- Un rând = un link generat de birou pentru un șofer anume, valabil 24h.
-- Șoferul (anonim) nu are voie să citească direct din tabelul asta — ajunge
-- la el doar prin funcția get_dossier_by_link de mai jos (security definer).

create table if not exists public.dossier_links (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_by uuid references auth.users(id)
);

alter table public.dossier_links enable row level security;

drop policy if exists "dossier_links_select_staff" on public.dossier_links;
create policy "dossier_links_select_staff" on public.dossier_links
  for select
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid()));

drop policy if exists "dossier_links_insert_staff" on public.dossier_links;
create policy "dossier_links_insert_staff" on public.dossier_links
  for insert
  to authenticated
  with check (exists (select 1 from public.profiles p where p.id = auth.uid()));

-- ============================================================================
-- 5) get_document_by_id — înlocuim funcția existentă
-- ============================================================================
-- Adaugă numele șoferului (din legătura nouă driver_id) și un flag is_expired,
-- ca șoferul să vadă mesaj clar dacă linkul a expirat. "doc_date" e convertit
-- explicit la text ca funcția să meargă indiferent dacă acea coloană e stocată
-- ca "date" sau ca "text" în baza voastră actuală.
-- security definer = rulează cu drepturile creatorului funcției, nu ale celui
-- care o apelează — de-asta poate citi "documents"/"drivers" chiar și pentru
-- rolul anonim, care altfel nu are voie.

-- drop întâi, ca să nu pice pe "cannot change return type of existing
-- function" dacă versiunea veche avea alte coloane în return.
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
  is_expired boolean
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
    (d.expires_at is not null and now() > d.expires_at and d.status = 'pending') as is_expired
  from public.documents d
  left join public.drivers dr on dr.id = d.driver_id
  where d.id = p_id;
$$;

grant execute on function public.get_document_by_id(uuid) to anon, authenticated;

-- ============================================================================
-- 6) get_dossier_by_link — nouă, pentru linkul "tot dosarul"
-- ============================================================================
-- O singură apelare întoarce: dacă linkul a expirat, numele șoferului, și
-- lista completă a documentelor lui ca JSON (json_agg) — clientul nu mai are
-- nevoie de un al doilea query. Dacă link_id nu există deloc, funcția
-- întoarce 0 rânduri (la fel ca get_document_by_id pentru un id inexistent).

create or replace function public.get_dossier_by_link(p_link_id uuid)
returns table (
  is_expired boolean,
  driver_full_name text,
  documents json
)
language sql
security definer
set search_path = public
as $$
  select
    (now() > l.expires_at) as is_expired,
    dr.full_name as driver_full_name,
    coalesce(
      (select json_agg(json_build_object(
          'id', d.id,
          'document_id', d.document_id,
          'title', d.title,
          'doc_type', d.doc_type,
          'doc_date', d.doc_date::text,
          'file_path', d.file_path,
          'file_type', d.file_type,
          'status', d.status
        ) order by d.doc_date)
       from public.documents d
       where d.driver_id = l.driver_id),
      '[]'::json
    ) as documents
  from public.dossier_links l
  join public.drivers dr on dr.id = l.driver_id
  where l.id = p_link_id;
$$;

grant execute on function public.get_dossier_by_link(uuid) to anon, authenticated;

-- ============================================================================
-- Gata. Nu s-a schimbat nimic la "signed_documents" sau la trigger-ul
-- compute_chain_hash — lanțul de audit rămâne exact cum era.
-- ============================================================================
