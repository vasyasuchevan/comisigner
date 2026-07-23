# ComiSigner

Sistem demonstrativ (temă de interviu) pentru semnarea electronică a documentelor de către șoferi, cu vizualizare centralizată în birou. Referință de arhitectură: [OpenSign](https://github.com/OpenSignLabs/OpenSign) (aplicație de semnat + panou web) — nu a fost copiat cod, doar logica generală "document → semnătură → arhivă verificabilă".

**Live:** https://comisigner.vercel.app
- `/driver/` — pagina pe care o deschide șoferul (link unic primit de la birou)
- `/office/` — panoul biroului (necesită autentificare)
- `/verify/` — verificare publică a unei semnături, fără autentificare, pe bază de link/cod

**Cod sursă:** https://github.com/vasyasuchevan/comisigner — `push` pe `main` declanșează automat un deploy nou în producție (integrare GitHub ↔ Vercel).

## Arhitectură

- **Frontend:** HTML/CSS/JS simplu, fără build step (fără React/Vite) — fiecare pagină e un singur fișier, ușor de deschis și testat direct.
- **Backend/bază de date/storage:** [Supabase](https://supabase.com) (Postgres + Auth + Storage), plan gratuit.
- **Hosting:** [Vercel](https://vercel.com), plan gratuit, deploy static, cu deploy automat din GitHub.
- **Aplicație mobilă:** [Capacitor](https://capacitorjs.com) — `/driver/` împachetat ca APK Android nativ, testat pe dispozitive reale.
- **Biblioteci:** [signature_pad](https://github.com/szimek/signature_pad) (semnătură desenată), `@supabase/supabase-js` (client), [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (coduri QR pentru linkurile de document) — toate încărcate local (`vendor/`), niciuna prin CDN.

### Flux principal

1. **Biroul** (`/office/`, după autentificare) încarcă un document (PDF sau imagine), completează traseul și data. Fișierul e stocat în Supabase Storage, iar biroul primește un **link unic** (`driver/?id=<uuid>`) + un **cod QR** generat automat, pe care le trimite șoferului.
2. **Șoferul** deschide linkul (sau scanează codul QR, sau introduce doar codul documentului manual), vede documentul direct în pagină, introduce numele și desenează semnătura pe `<canvas>`.
3. La apăsarea „Semnează": documentul e **descărcat din nou** și hashuit pe loc (nu se are încredere într-o valoare salvată anterior), imaginea semnăturii e încărcată în Storage, iar hash-ul SHA-256 e calculat din:

   `hash = SHA256(hash_document + semnătură_dataURL + marcă_temporală_ISO8601 + ID_dispozitiv)`

   În plus, această înregistrare e **înlănțuită criptografic** de cea anterioară (vezi secțiunea următoare). Documentul e marcat automat ca „semnat" printr-un trigger Postgres, fără a acorda drept de UPDATE clientului anonim. După semnare, șoferul primește instant un **link de verificare publică**.
4. **Biroul** vede lista completă (documente în așteptare + semnate), poate deschide orice document semnat, apăsa **„Verifică integritatea"** (recalculează hash-ul de la zero) sau **„Verifică lanțul complet"** (validează tot jurnalul de audit dintr-o dată).

### Lanțul de audit (tamper-evident chain)

Fiecare semnătură nouă înglobează hash-ul celei precedente:

```
chain_hash = SHA256(chain_hash_precedent (sau 'GENESIS' pentru prima) + '|' + hash_înregistrării)
```

Efectul: dacă cineva ar modifica sau șterge o înregistrare mai veche direct din baza de date (ocolind aplicația), toate înregistrările ulterioare din lanț nu s-ar mai potrivi cu valoarea recalculată — ruptura e vizibilă matematic, nu doar "pe încredere". Nu e nevoie de blockchain sau criptomonede pentru asta — doar un trigger Postgres (`compute_chain_hash`, security definer) care calculează câmpul la fiecare inserare.

Verificarea e disponibilă în două locuri independente:
- **`/office/`** → butonul „Verifică lanțul complet" — parcurge tot jurnalul și recalculează fiecare verigă.
- **`/verify/?id=...`** → pagină publică, fără login, care recalculează independent poziția unei singure înregistrări în lanț (folosită de client/arhivă/instanță, dacă e cazul).

### Schema Supabase (pe scurt)

- `documents` — documentele încărcate de birou (`title`, `route`, `doc_date`, `file_path`, `file_type`, `status`: pending/signed). Fără acces direct pentru anonim — doar prin RPC `get_document_by_id`.
- `signed_documents` — evenimentele de semnare (`driver_name`, `device_id`, `signature_path`, `hash`, `signed_at`, `document_ref`, `seq`, `prev_chain_hash`, `chain_hash`). **Fără politici RLS de `update`/`delete`** pentru niciun rol client — tabelă append-only, ca un registru de audit.
- RPC `get_document_by_id(uuid)` — singurul mod în care un șofer neautentificat poate citi un document, exact pe cel al cărui link/cod îl are.
- RPC `verify_signed_document(uuid)` — folosit de pagina publică `/verify/`, fără autentificare, întoarce o singură înregistrare + metadatele documentului.
- Storage: bucket `documents` (public pe cale exactă, nelistabil), bucket `signatures` (privat, acces doar autentificat prin URL semnat temporar, 1 oră).

## ⚖️ Notă juridică importantă — nivelul de semnătură electronică

Conform eIDAS (Regulamentul UE 910/2014), există trei niveluri de semnătură electronică:

1. **Semnătură electronică simplă (SES)** — un desen pe ecran, fără nimic altceva. Ușor de contestat în instanță, pentru că nu leagă criptografic semnătura de conținutul exact al documentului.
2. **Semnătură electronică avansată (AES)** — necesită: identificarea univocă a semnatarului, o legătură care permite detectarea oricărei modificări ulterioare a datelor semnate, și control exclusiv al semnatarului asupra datelor de creare a semnăturii. **Acesta este nivelul la care s-a construit acest prototip**: hash SHA-256 care leagă criptografic documentul + semnătura + timpul + dispozitivul, plus un lanț de audit care extinde garanția la nivelul întregului registru, nu doar la o singură semnătură.
3. **Semnătură electronică calificată (QES)** — cel mai înalt nivel, cu aceeași valoare juridică ca semnătura olografă în UE. **Necesită un furnizor acreditat de servicii de încredere** (ex. în România: **certSIGN**, **DigiSign**), certificat digital calificat emis pe baza unei verificări de identitate riguroase, și de regulă un dispozitiv criptografic dedicat. **Acest nivel este în afara scopului acestui prototip.**

**Limitări cunoscute** (transparență, nu ascundem):
- **ID dispozitiv** e un UUID generat local (browser/aplicație), nu un fingerprint hardware securizat.
- **Nicio verificare de identitate** a șoferului la semnare (nume introdus liber).
- **Bucket-ul `documents` e public** pe cale exactă (nelistabil) — prag de confidențialitate mai jos decât arhiva de semnături (care necesită login).
- **APK-ul Android e o build de tip debug**, nesemnată pentru Google Play — pentru publicare ar fi nevoie de o cheie de semnare release.
- **Un cod QR scanat deschide mereu versiunea web** (în browser), nu direct aplicația nativă instalată — pentru asta ar fi nevoie de Android App Links (verificare de domeniu), neconfigurat încă. Funcțional identic — codul e același în ambele.

## Structura proiectului

```
/                   — pagină de start (alege șofer / birou)
/driver/            — aplicația șoferului (PWA + sursă pentru build-ul Android)
/office/            — panoul biroului (autentificare Supabase, upload documente, verificare)
/verify/            — verificare publică a unei semnături, fără autentificare
/mobile/            — proiect Capacitor pentru build-ul Android nativ (APK)
```

## Aplicația mobilă (Android)

`mobile/` conține un proiect Capacitor Android standard (`webDir` indică spre `../driver`, deci fișierele nu se duplică). Build prin linia de comandă (JDK 21 + Android SDK command-line tools, fără Android Studio complet):

```
cd mobile
npx cap sync android
cd android
gradlew.bat assembleDebug
```

Rezultat: `mobile/android/app/build/outputs/apk/debug/app-debug.apk` — instalabil direct pe Android (sursă necunoscută). **Testat cu succes pe două dispozitive Android reale**, inclusiv fluxul complet: primire link, semnare, verificare. `/driver/` rămâne și el instalabil ca PWA direct din Chrome ("Adaugă pe ecranul principal"), funcțional identic.

## Dezvoltare locală / testare / deploy

Fiecare pagină e un fișier HTML de sine stătător, cu biblioteci încărcate local (`vendor/`) — se poate deschide direct în browser sau servi static. Cheia Supabase folosită în cod e cheia publică ("publishable"/anon) — protejată prin Row Level Security pe server, nu printr-un secret ascuns în client.

Controlul de versiuni se face prin Git, cu istoricul complet pe GitHub. Vercel e conectat direct la repository — orice `push` pe `main` pornește automat un build și un deploy nou în producție, fără pași manuali.
