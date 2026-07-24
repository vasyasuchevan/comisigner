---
name: rebuild-apk
description: Rebuild the ComiSigner Android APK (debug or signed release) from the current driver/ code and copy it to the Desktop. Use this whenever driver/index.html (or anything else under driver/) has changed and the user needs an updated APK to test or share — e.g. "rebuild the apk", "make a new apk", "package the app again", "sync and build android", "send me a fresh build", "build a release apk". Handles the exact env vars and build order this project's Capacitor setup needs, so they don't have to be re-derived each time.
---

# Rebuild ComiSigner Android APK

Wraps the multi-step Capacitor Android build sequence for this repo so the env var paths and build order don't need to be re-derived every time. Two build types exist now — debug (default, for quick testing) and signed release (for anything closer to real distribution). Ask which one the user wants if it's not obvious from context; default to debug for routine "test this change" requests.

## Why the order matters

`npx cap sync android` copies the current contents of `driver/` into the Android project's bundled assets (`android/app/src/main/assets/public`). If the build runs **before** `cap sync`, or `cap sync` is skipped, the APK ships stale code — this happened for real earlier in the project (an APK went out with pre-Stage-6 driver code because sync ran too early). Always sync immediately before building.

## Steps

Run from the repo root (`C:\Users\Anisoara\OneDrive\Desktop\ComiSigner`):

```bash
cd mobile
export PATH="/c/Program Files/nodejs:$PATH"
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
export ANDROID_HOME="/c/Android/Sdk"
export ANDROID_SDK_ROOT="/c/Android/Sdk"
npx cap sync android
cd android
./gradlew.bat assembleDebug --no-daemon
```

JDK must be version 21 — JDK 17 fails this build with `invalid source release: 21`. If the `JAVA_HOME` path above no longer exists on this machine, locate the installed JDK 21 path first rather than guessing or falling back to a different version.

## After a successful build

Copy the APK to the Desktop — this is the file the user hands to other people to test:

```bash
cp "/c/Users/Anisoara/OneDrive/Desktop/ComiSigner/mobile/android/app/build/outputs/apk/debug/app-debug.apk" "/c/Users/Anisoara/OneDrive/Desktop/ComiSigner-app.apk"
```

Report plainly whether the build succeeded, and confirm the file is on the Desktop.

## Important limitation — always say this out loud (debug build only)

A debug build (`assembleDebug`) is **unsigned**, not something installable from Google Play or usable as a real update to a previously-installed release build. For anything beyond quick local testing, use the release build below instead.

## Release build (signed)

As of 2026-07-24 a real release keystore exists — see [[reference-comisigner-infra]] for its exact path. `mobile/android/app/build.gradle` reads signing credentials from `mobile/android/keystore.properties` (git-ignored, contains the store/key passwords in plaintext — never print its contents or commit it). If that file is missing on this machine, `assembleRelease` silently falls back to producing an **unsigned** release APK (Gradle logs a warning) — check for that file first rather than assuming signing will happen.

```bash
cd mobile
export PATH="/c/Program Files/nodejs:$PATH"
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
export ANDROID_HOME="/c/Android/Sdk"
export ANDROID_SDK_ROOT="/c/Android/Sdk"
npx cap sync android
cd android
./gradlew.bat assembleRelease --no-daemon
cp app/build/outputs/apk/release/app-release.apk "/c/Users/Anisoara/OneDrive/Desktop/ComiSigner-release.apk"
```

To confirm an APK is actually signed with the real key (not accidentally unsigned), verify with apksigner from the newest installed build-tools version:

```bash
/c/Android/Sdk/build-tools/<version>/apksigner.bat verify --print-certs app/build/outputs/apk/release/app-release.apk
```

Expect `CN=Comilga, OU=ComiSigner, O=Comilga, L=Bucuresti, ST=Bucuresti, C=RO` in the output. **Never regenerate the keystore** — losing it means every future release breaks the upgrade path for anyone who already installed a build signed with it. If `keystore.properties` or the `.jks` file is ever missing, stop and ask the user before creating a new one.

## If the build fails

Show the actual Gradle error rather than guessing at the cause. Two failure modes already seen on this project: wrong JDK version (`invalid source release`), or a fresh machine missing Android SDK licenses (`sdkmanager --licenses`, accepted via `yes | sdkmanager --licenses` in Bash — PowerShell piping into it doesn't work).
