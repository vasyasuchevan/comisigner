---
name: rebuild-apk
description: Rebuild the ComiSigner Android debug APK from the current driver/ code and copy it to the Desktop. Use this whenever driver/index.html (or anything else under driver/) has changed and the user needs an updated APK to test or share — e.g. "rebuild the apk", "make a new apk", "package the app again", "sync and build android", "send me a fresh build". Handles the exact env vars and build order this project's Capacitor setup needs, so they don't have to be re-derived each time.
---

# Rebuild ComiSigner Android APK

Wraps the multi-step Capacitor Android build sequence for this repo so the env var paths and build order don't need to be re-derived every time.

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

## Important limitation — always say this out loud

This produces an **unsigned debug build only**, not something installable from Google Play. Fixing that (a release keystore + signed build) is a separate, not-yet-built process — one of two things the user's job-interview follow-up explicitly needs. Don't describe a debug rebuild as "release-ready" or imply it satisfies that requirement.

## If the build fails

Show the actual Gradle error rather than guessing at the cause. Two failure modes already seen on this project: wrong JDK version (`invalid source release`), or a fresh machine missing Android SDK licenses (`sdkmanager --licenses`, accepted via `yes | sdkmanager --licenses` in Bash — PowerShell piping into it doesn't work).
