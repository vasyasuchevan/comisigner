# ComiSigner

Sistem demonstrativ (temă de interviu) pentru semnarea electronică a documentelor de către șoferi, cu vizualizare centralizată în birou. Referință de arhitectură: [OpenSign](https://github.com/OpenSignLabs/OpenSign) (aplicație de semnat + panou web) — nu a fost copiat cod, doar logica generală "document → semnătură → arhivă verificabilă".

**Live:** https://comisigner.vercel.app
- `/driver/` — pagina pe care o deschide șoferul (link unic primit de la birou)
- `/office/` — panoul biroului (necesită autentificare)

## Arhitectură

- **Frontend:** HTML/CSS/JS simplu, fără build step (fără React/Vite) — fiecare pagină e un singur fișier, ușor de deschis și testat direct.
- **Backend/bază de date/storage:** [Supabase](https://supabase.com) (Postgres + Auth + Storage), plan gratuit.
- **Hosting:** [Vercel](https://vercel.com), plan gratuit, deploy static.
- **Semnătură desenată:** [signature_pad](https://github.com/szimek/signature_pad) (bibliotecă standard, 9k+ stele pe GitHub), încărcată local (nu de pe CDN) pentru funcționare offline.
- **Client Supabase:** `@supabase/supabase-js`, de asemenea local, nu prin CDN.

### Flux principal

1. **Biroul** (`/office/`, după autentificare) încarcă un document (PDF sau imagine — o factură/aviz), completează traseul și data. Fișierul e stocat în Supabase Storage, iar biroul primește un **link unic** de forma `driver/?id=<uuid>`, pe care îl trimite șoferului (WhatsApp, SMS etc.).
2. **Șoferul** deschide linkul, vede documentul (PDF/imagine) direct în pagină, introduce numele și desenează semnătura pe `<canvas>`.
3. La apăsarea „Semnează”: documentul e **descărcat din nou** și hashuit pe loc (nu se are încredere într-o valoare salvată anterior — orice modificare a fișierului între încărcare și semnare ar fi detectată), imaginea semnăturii e încărcată în Storage, iar un hash SHA-256 unic e calculat din:

   `hash(fișier document + imagine semnătură + marcă temporală ISO 8601 + ID dispozitiv)`

   Acest hash, împreună cu toate componentele sale, e salvat în tabela `signed_documents`. Documentul e marcat automat ca „semnat” printr-un trigger Postgres (fără a acorda drept de UPDATE clientului anonim).
4. **Biroul** vede lista completă (documente în așteptare + semnate), poate deschide orice document semnat și apăsa **„Verifică integritatea”** — pagina redescarcă documentul și semnătura din Storage, recalculează hash-ul de la zero și îl compară cu cel salvat. Orice modificare ulterioară semnării (a documentului, semnăturii sau metadatelor) face ca verificarea să eșueze vizibil.

### Schema Supabase (pe scurt)

- `documents` — documentele încărcate de birou (`title`, `route`, `doc_date`, `file_path`, `file_type`, `status`: pending/signed).
- `signed_documents` — evenimentele de semnare (`driver_name`, `device_id`, `signature_path`, `hash`, `signed_at`, `document_ref` → `documents.id`). Nu există politici RLS de `update`/`delete` pentru rolurile client — tabela e append-only din perspectiva aplicației, ca un registru de audit.
- RPC `get_document_by_id(uuid)` — singurul mod în care un șofer neautentificat poate citi un document, exact pe cel al cărui link îl are (nu poate lista toate documentele).
- Storage: bucket `documents` (public, pentru documentele de semnat), bucket `signatures` (privat, accesibil doar autentificat prin URL semnat temporar).

## ⚖️ Notă juridică importantă — nivelul de semnătură electronică

Conform eIDAS (Regulamentul UE 910/2014), există trei niveluri de semnătură electronică:

1. **Semnătură electronică simplă (SES)** — un desen pe ecran, fără nimic altceva. Ușor de contestat în instanță, pentru că nu leagă criptografic semnătura de conținutul exact al documentului.
2. **Semnătură electronică avansată (AES)** — necesită: identificarea univocă a semnatarului, o legătură care permite detectarea oricărei modificări ulterioare a datelor semnate, și control exclusiv al semnatarului asupra datelor de creare a semnăturii. **Acesta este nivelul la care s-a construit acest prototip**: hash SHA-256 care leagă criptografic documentul + semnătura + timpul + dispozitivul, verificabil oricând ulterior.
3. **Semnătură electronică calificată (QES)** — cel mai înalt nivel, cu aceeași valoare juridică ca semnătura olografă în UE. **Necesită un furnizor acreditat de servicii de încredere** (ex. în România: **certSIGN**, **DigiSign**), certificat digital calificat emis pe baza unei verificări de identitate riguroase, și de regulă un dispozitiv criptografic dedicat (token/HSM). **Acest nivel este în afara scopului acestui prototip** — implementarea lui ar necesita integrarea cu un furnizor QES acreditat, cost și infrastructură pe care un prototip de interviu nu le poate justifica.

**Limitări cunoscute ale nivelului AES implementat aici** (transparență, nu ascundem):
- **ID dispozitiv** e un UUID generat în `localStorage` — un identificator la nivel de browser/instalare, nu un fingerprint hardware securizat. Pe o aplicație mobilă nativă, ar fi înlocuit cu un ID de dispozitiv la nivel de OS.
- **Nicio verificare de identitate** a șoferului la semnare (nume introdus liber, fără OTP/verificare de document). Un sistem de producție ar adăuga autentificare a șoferului.
- **Bucket-ul `documents` e public** (citire după cale exactă, dar necunoscută/nelistabilă) — suficient pentru un link „oricine are linkul” către o factură înainte de semnare, dar nu e o restricție de acces la fel de strictă ca la arhiva de documente semnate (care necesită login).

## Structura proiectului

```
/                   — pagină de start (alege șofer / birou)
/driver/            — aplicația șoferului (PWA, funcționează offline pentru interfață)
/office/            — panoul biroului (autentificare Supabase, upload documente, verificare)
/mobile/            — proiect Capacitor pentru build-ul Android nativ (APK)
```

## Aplicația mobilă (Android)

Am încercat două căi, în ordinea din care s-a pornit:

1. **APK nativ prin Capacitor** — `mobile/` conține un proiect Capacitor Android standard (`webDir` indică spre `../driver`, deci nu se duplică niciun fișier). Build prin linia de comandă (JDK + Android SDK command-line tools, fără Android Studio complet):
   ```
   cd mobile/android
   gradlew.bat assembleDebug
   ```
   Rezultat: `mobile/android/app/build/outputs/apk/debug/app-debug.apk` — instalabil direct pe Android (sursă necunoscută) sau prin `adb install`. **E o build de tip debug**, nesemnată pentru Google Play — pentru publicare ar fi nevoie de o cheie de semnare release, în afara scopului acestui prototip.
2. **PWA (progressive web app)** — dacă build-ul nativ ar fi blocat definitiv de incompatibilități de versiuni SDK/Gradle, `/driver/` e deja instalabilă direct din Chrome pe Android ("Adaugă pe ecranul principal"), funcționează offline pentru interfață (service worker), fără Android Studio. A rămas ca variantă funcțională indiferent de rezultatul build-ului APK.

## Dezvoltare locală / testare

Fiecare pagină e un fișier HTML de sine stătător, cu biblioteci încărcate local (`vendor/`) — se poate deschide direct în browser sau servi static (Vercel, orice server static). Cheia Supabase folosită în cod e cheia publică ("publishable"/anon) — protejată prin Row Level Security pe server, nu printr-un secret ascuns în client.
