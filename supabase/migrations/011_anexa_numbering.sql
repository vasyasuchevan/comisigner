-- ComiSigner — migrația 011: numerotare automată a anexelor (registru de acte)
--
-- Rulați integral în Supabase Dashboard → SQL Editor (rulează ca rol "postgres",
-- ocolește RLS). Scris să poată fi rulat de mai multe ori fără erori.
--
-- De ce: anexele CIM (Anexa 1/3/5…) au nevoie de un număr de înregistrare/act care
-- să se atribuie AUTOMAT, în ordine, în loc să fie scris de mână. Ținem un contor
-- per "registru" (un nume de registru, ex. 'registru_acte') și per an calendaristic,
-- ca numerotarea să repornească de la 1 în fiecare an (ex. nr. 128 / 2026).
--
-- Model de acces: contorul NU trebuie citit/scris direct de nimeni din aplicație —
-- se atinge doar prin funcția next_anexa_number(), care e "security definer" (rulează
-- cu drepturi de owner, ocolind RLS) și e disponibilă doar utilizatorilor autentificați
-- (biroul), nu și anonimilor (șoferii). Așa nu se poate sări peste numere sau falsifica
-- registrul din client.

-- ============================================================================
-- 1) Tabelul contor: o linie = un registru într-un an, cu ultima valoare emisă
-- ============================================================================
create table if not exists public.anexa_counters (
  register text not null,
  year     int  not null,
  value    int  not null default 0,
  primary key (register, year)
);

-- RLS activat FĂRĂ nicio politică = nimeni (anon sau authenticated) nu poate citi
-- sau scrie direct în tabel. Singura cale e funcția de mai jos.
alter table public.anexa_counters enable row level security;

-- (Ne asigurăm că nu rămân granturi implicite către rolurile aplicației.)
revoke all on table public.anexa_counters from anon, authenticated;

-- ============================================================================
-- 2) Funcția care emite următorul număr, atomic
-- ============================================================================
-- Incrementează și întoarce următoarea valoare pentru (registru, anul curent).
-- "on conflict ... do update" face operația atomică sub un lock de rând, deci doi
-- utilizatori care generează în același timp nu pot primi același număr.
create or replace function public.next_anexa_number(p_register text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year int := extract(year from now())::int;
  v_val  int;
begin
  if p_register is null or length(trim(p_register)) = 0 then
    raise exception 'register name is required';
  end if;

  insert into public.anexa_counters (register, year, value)
  values (p_register, v_year, 1)
  on conflict (register, year)
  do update set value = public.anexa_counters.value + 1
  returning value into v_val;

  return v_val;
end;
$$;

-- Doar biroul (authenticated) poate cere un număr; anonimul (șoferul) nu.
revoke all on function public.next_anexa_number(text) from public, anon;
grant execute on function public.next_anexa_number(text) to authenticated;
