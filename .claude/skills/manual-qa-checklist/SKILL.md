---
name: manual-qa-checklist
description: Structured manual test pass for a ComiSigner change before calling it done. Use after any change to driver/, office/, or verify/, and especially before rebuilding the APK or telling the user something is ready to demo or send to someone else.
---

# ComiSigner manual QA pass

Every real bug found on this project so far was found through live testing, not code review — a broken verification link and a double-signing bug were both invisible in browser-only testing and only showed up on real Android devices. Before saying a change is done, walk it live rather than trusting the code alone.

## What to check, based on what changed

- **Driver flow**: cold start (no `?id` in the URL) shows the welcome screen without depending on JS having run; opening a valid pending document works; signing succeeds and can't be repeated (buttons must stay disabled after a successful signature, canvas frozen); the verify link generated points at the real production domain, not `localhost` — this exact bug shipped once already, from `location.origin` resolving differently inside the Capacitor WebView versus a normal browser.
- **Office flow**: login, upload, list, "Verifică integritatea", "Verifică lanțul complet" — click every button, don't just read the code.
- **Verify page**: open with a real id, and with a missing/garbage id, confirm both render sensibly.
- **If driver/ changed and an APK matters right now**: a code change alone does not update what's on anyone's phone — that only happens after `/rebuild-apk` is run and the new file is actually sent out.
- **Cross-role checks, once roles exist**: confirm each role actually can't do what it shouldn't, not just that it can do what it should — the interesting bugs in an RLS-based system are usually permission leaks, not permission blocks.
- **Trip/folder batch signing, once it exists**: test resuming a partially-signed trip (sign 2 of 5, close the tab, reopen the link) and confirm already-signed documents in the batch stay locked while the rest remain available.

## Reporting back

State plainly what was actually clicked and on what — browser, emulator, or a real device — and don't describe something as "tested" if it was only reasoned about from the code. The user has caught real bugs specifically because he insists on this distinction.
