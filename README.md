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
- **Biblioteci:** [signature_pad](https://github.com/szimek/signature_pad) (semnătură desenată), `@supabase/supabase-js` (client), [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (coduri QR pentru linkurile de document), [pdf.js](https://mozilla.github.io/pdf.js/) (randare PDF pe `<canvas>`), [Tesseract.js](https://github.com/naptha/tesseract.js) (OCR, pentru plasarea automată a semnăturii — vezi mai jos) și [pdf-lib](https://pdf-lib.js.org/) (compune imaginea semnăturii peste o copie a PDF-ului) — toate încărcate local (`vendor/`), niciuna prin CDN.

### Roluri și dosarul șoferului

Personalul biroului are un rol — **Admin** (acces complet) sau **HR** (adaugă șoferi, adaugă documente, trimite linkuri) — atribuit manual printr-un rând în tabelul `profiles` (nu există o pagină de "creează cont" în aplicație, ca să nu fie nevoie de o cheie service_role; conturile Auth se creează din Supabase Dashboard). Fiecare **șofer** are un dosar de documente (acte necesare angajării sau reînnoirii — permis, certificat medical etc.), nu documente de transport. Biroul poate genera două tipuri de linkuri pentru un șofer, ambele **valabile 24h**:

- link către **un singur document** din dosar;
- link către **tot dosarul** — șoferul vede toate documentele unul după altul și le semnează pe toate **cu o singură semnătură** (fiecare document primește totuși propria înregistrare în jurnalul de audit, vezi mai jos).

### Flux principal

1. **Biroul** (`/office/`, după autentificare) adaugă un șofer, apoi încarcă un document (PDF sau imagine) în dosarul lui, cu titlu, tip de document și dată. Fișierul e stocat în Supabase Storage, iar biroul primește un **link unic** (`driver/?id=<uuid>`, valabil 24h) + un **cod QR** generat automat, pe care le trimite șoferului — sau generează un link pentru tot dosarul (`driver/?dossier=<uuid>`).
2. **Șoferul** deschide linkul (sau scanează codul QR, sau introduce doar codul documentului manual), vede documentul (sau toate documentele din dosar) direct în pagină, bifează o declarație că a citit documentul/documentele, și desenează semnătura pe `<canvas>`.
3. La apăsarea „Semnează": documentul e **descărcat din nou** și hashuit pe loc (nu se are încredere într-o valoare salvată anterior), imaginea semnăturii e încărcată în Storage, iar hash-ul SHA-256 e calculat din:

   `hash = SHA256(hash_document + semnătură_dataURL + marcă_temporală_ISO8601 + ID_dispozitiv)`

   În plus, această înregistrare e **înlănțuită criptografic** de cea anterioară (vezi secțiunea următoare). Documentul e marcat automat ca „semnat" printr-un trigger Postgres, fără a acorda drept de UPDATE clientului anonim. După semnare, șoferul primește instant un **link de verificare publică**.
4. **Biroul** vede lista completă (documente în așteptare + semnate), poate deschide orice document semnat — vede documentul cu semnătura compusă vizual peste el (vezi mai jos) —, apăsa **„Verifică integritatea"** (recalculează hash-ul de la zero, pe fișierul original) sau **„Verifică lanțul complet"** (validează tot jurnalul de audit dintr-o dată).

### Copia „ștampilată" (semnătura compusă vizual peste document)

Hash-ul de audit se calculează mereu pe fișierul **original, nemodificat** (altfel n-ar mai detecta o manipulare ulterioară) — dar un hash nu e ceva ce oamenii vor să se uite la el. De-asta, imediat după calcularea hash-ului, clientul generează **o a doua copie**, cu imaginea semnăturii desenate compusă vizual peste document (pdf-lib pentru PDF — pe pagina și în locul unde OCR-ul de mai sus a găsit rândul de semnătură, dacă a găsit; `<canvas>` pentru imagini, colț dreapta-jos), o încarcă separat (bucket `signed_files`), și abia asta se afișează în `/office/`. Dacă generarea copiei eșuează din orice motiv, semnarea tot reușește — copia ștampilată e strict cosmetică, nu participă la hash sau la lanțul de audit.

### Plasare automată a semnăturii (OCR local, independent de limbă)

Pentru linkul către **un singur document** (nu și pentru dosar întreg, unde o singură semnătură acoperă toate documentele oricum), aplicația încearcă să găsească automat rândul de semnătură din PDF: documentul e randat pagină cu pagină pe `<canvas>` (via pdf.js, în loc de vizualizatorul nativ `<embed>`, care oricum nu funcționează de regulă în WebView-ul Android folosit de APK), apoi rulează OCR local (Tesseract.js, `ron+eng+rus+ukr` într-o singură trecere, fără server, fără CDN) căutând un cuvânt-cheie într-o listă multilingvă ("semnătură", "subsemnatul", "signature", "подпись", "підпис", "podpis" — polonă, "unterschrift" — germană, "firma" — italiană/spaniolă/portugheză, ultimele trei citite direct de modelele ron/eng, fără pachet de limbă separat) — pornind de la **ultima pagină** înapoi (acolo e aproape mereu linia de semnătură), limitat la 3 pagini și la un buget de 14 secunde. Dacă găsește mai multe cuvinte-cheie pe aceeași pagină (ex. "subsemnatul" într-o propoziție de declarație, apoi "semnătura" mai jos, la rândul propriu-zis), preferă cuvântul care numește direct semnătura ("semnătură"/"signature"/"подпись") în locul celui contextual ("subsemnatul"), iar la egalitate pe cel mai de jos de pe pagină — rândul real de semnătură vine aproape mereu după orice menționare anterioară în text. Dacă găsește ceva, afișează un indicator chiar în document și mută cardul de semnat lângă el; dacă nu găsește nimic, timpul expiră, sau OCR-ul eșuează din orice motiv, aplicația revine tăcut la comportamentul dinainte (documentul cu `<embed>`, cardul de semnat la finalul paginii) — niciodată nu blochează semnarea. Randarea pe `<canvas>` e la rândul ei plafonată la 15 pagini (un contract de 50 de pagini nu trebuie să țină 50 de imagini în memoria telefonului) — peste acest prag se randează primele pagini plus mereu ultimele 3 (de care are nevoie OCR-ul), cu un mesaj pentru paginile omise și linkul „deschide într-o filă nouă" pentru inspecție completă.

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

- `profiles` — leagă un login din Supabase Auth de un rol (`admin` sau `hr`). Un rând aici e ceea ce transformă un login în membru autorizat al echipei; se adaugă manual din Table Editor.
- `drivers` — șoferii (`full_name`, `phone`). Citire/scriere doar pentru cineva cu rând în `profiles`.
- `documents` — documentele din dosarul unui șofer (`driver_id`, `title`, `doc_type`, `doc_date`, `file_path`, `file_type`, `status`: pending/signed, `expires_at`). Fără acces direct pentru anonim — doar prin RPC-urile de mai jos.
- `dossier_links` — token-ul (folosit direct ca id în URL) pentru linkul "tot dosarul", cu `driver_id` și `expires_at` (24h de la generare).
- `signed_documents` — evenimentele de semnare (`driver_name`, `device_id`, `signature_path`, `stamped_file_path`, `hash`, `signed_at`, `document_ref`, `seq`, `prev_chain_hash`, `chain_hash`). **Fără politici RLS de `update`/`delete`** pentru niciun rol client — tabelă append-only, ca un registru de audit. `stamped_file_path` e strict pentru afișare (vezi „Copia ștampilată" mai sus) — poate fi `NULL` (generare eșuată sau înregistrare mai veche) fără să afecteze validitatea semnării. La semnarea unui întreg dosar, se inserează câte un rând per document (aceeași imagine de semnătură, aceeași marcă temporală), nu un singur rând agregat — fiecare document își păstrează propria verigă în lanțul de audit.
- RPC `get_document_by_id(uuid)` — singurul mod în care un șofer neautentificat poate citi un document, exact pe cel al cărui link/cod îl are; întoarce și numele șoferului și dacă linkul a expirat.
- RPC `get_dossier_by_link(uuid)` — la fel, pentru linkul "tot dosarul": numele șoferului, starea de expirare, și lista completă a documentelor lui.
- RPC `verify_signed_document(uuid)` — folosit de pagina publică `/verify/`, fără autentificare, întoarce o singură înregistrare + metadatele documentului.
- Storage: bucket `documents` (public pe cale exactă, nelistabil), bucket `signatures` (privat, acces doar autentificat prin URL semnat temporar, 1 oră), bucket `signed_files` (public pe cale exactă, la fel ca `documents` — copiile ștampilate, scrise de șofer/rol anonim la semnare).
- Migrațiile SQL sunt în `supabase/migrations/` (rulate manual în Supabase Dashboard → SQL Editor — proiectul nu folosește Supabase CLI).

## ⚖️ Notă juridică importantă — nivelul de semnătură electronică

Conform eIDAS (Regulamentul UE 910/2014), există trei niveluri de semnătură electronică:

1. **Semnătură electronică simplă (SES)** — un desen pe ecran, fără nimic altceva. Ușor de contestat în instanță, pentru că nu leagă criptografic semnătura de conținutul exact al documentului.
2. **Semnătură electronică avansată (AES)** — necesită: identificarea univocă a semnatarului, o legătură care permite detectarea oricărei modificări ulterioare a datelor semnate, și control exclusiv al semnatarului asupra datelor de creare a semnăturii. **Acesta este nivelul la care s-a construit acest prototip**: hash SHA-256 care leagă criptografic documentul + semnătura + timpul + dispozitivul, plus un lanț de audit care extinde garanția la nivelul întregului registru, nu doar la o singură semnătură.
3. **Semnătură electronică calificată (QES)** — cel mai înalt nivel, cu aceeași valoare juridică ca semnătura olografă în UE. **Necesită un furnizor acreditat de servicii de încredere** (ex. în România: **certSIGN**, **DigiSign**), certificat digital calificat emis pe baza unei verificări de identitate riguroase, și de regulă un dispozitiv criptografic dedicat. **Acest nivel este în afara scopului acestui prototip.**

**Limitări cunoscute** (transparență, nu ascundem):
- **ID dispozitiv** e un UUID generat local (browser/aplicație), nu un fingerprint hardware securizat.
- **Nicio verificare de identitate reală** a șoferului la semnare — numele afișat la semnare vine acum din dosarul creat de birou (nu mai e introdus liber de șofer, cu excepția linkurilor vechi, dinainte de introducerea dosarelor), dar asta confirmă doar că cineva cu acces la link a semnat ca acel șofer, nu identitatea lui reală (nu e o verificare de tip ID/video, cum cere QES).
- **Bucket-ul `documents` e public** pe cale exactă (nelistabil) — prag de confidențialitate mai jos decât arhiva de semnături (care necesită login).
- ~~**APK-ul Android e o build de tip debug**, nesemnată pentru Google Play~~ — rezolvat: există acum o build `assembleRelease` semnată cu un keystore de producție dedicat (vezi secțiunea „Build semnată" de mai sus).
- **Un cod QR scanat deschide mereu versiunea web** (în browser), nu direct aplicația nativă instalată — pentru asta ar fi nevoie de Android App Links (verificare de domeniu), neconfigurat încă. Funcțional identic — codul e același în ambele.
- **Plasarea automată a semnăturii e o euristică, nu o garanție** — OCR-ul local poate rata linia de semnătură (scan de calitate slabă, format neobișnuit, altă limbă decât cele acoperite — momentan română, engleză, rusă, ucraineană prin OCR dedicat, plus polonă/germană/italiană-spaniolă-portugheză prin cuvinte-cheie citite de modelele existente), caz în care aplicația revine automat la afișarea simplă a documentului, fără să blocheze semnarea. Bibliotecile OCR + PDF adaugă ~16 MB la `driver/` (deci și la APK).

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

Rezultat: `mobile/android/app/build/outputs/apk/debug/app-debug.apk` — build de test, **nesemnată**, instalabilă direct pe Android (sursă necunoscută). **Testat cu succes pe două dispozitive Android reale**, inclusiv fluxul complet: primire link, semnare, verificare. `/driver/` rămâne și el instalabil ca PWA direct din Chrome ("Adaugă pe ecranul principal"), funcțional identic.

### Build semnată (release)

Există un keystore de producție (`comisigner`, valabil 10.000 zile) — **nu e în repo** (secret, exclus prin `.gitignore`), stocat local la `C:\Users\Anisoara\OneDrive\Desktop\ComiSigner-release-key.jks`, cu parola în `mobile/android/keystore.properties` (tot exclus din git). `app/build.gradle` citește automat acest fișier și semnează orice `assembleRelease`; dacă fișierul lipsește, Gradle produce o build **nesemnată** și afișează un avertisment în log, fără să eșueze silențios.

```
cd mobile
npx cap sync android
cd android
gradlew.bat assembleRelease
```

Rezultat: `mobile/android/app/build/outputs/apk/release/app-release.apk`, semnată cu certificatul `CN=Comilga, OU=ComiSigner, O=Comilga, L=Bucuresti, ST=Bucuresti, C=RO` (verificabil cu `apksigner verify --print-certs`). **Keystore-ul nu trebuie regenerat niciodată** — orice actualizare viitoare a aplicației, inclusiv o eventuală publicare pe Google Play, trebuie semnată cu același keystore; pierderea lui rupe iremediabil lanțul de actualizări pentru oricine a instalat deja o build semnată cu el.

## Dezvoltare locală / testare / deploy

Fiecare pagină e un fișier HTML de sine stătător, cu biblioteci încărcate local (`vendor/`) — se poate deschide direct în browser sau servi static. Cheia Supabase folosită în cod e cheia publică ("publishable"/anon) — protejată prin Row Level Security pe server, nu printr-un secret ascuns în client.

Controlul de versiuni se face prin Git, cu istoricul complet pe GitHub. Vercel e conectat direct la repository — orice `push` pe `main` pornește automat un build și un deploy nou în producție, fără pași manuali.
