# AI Handoff Log — Neighbourly (e_commerce_app)

This file is the running source of truth between AI coding sessions/tools
(Claude, Codex, etc.) working on this repo. **Read this file and `git log`
before starting anything new.** After finishing a task, add a new entry at
the top of the Log section (newest first) and commit it along with the code.

Do not delete old entries — this is a history, not a status snapshot.
`BUILD_STATUS.md` and `docs/*.md` are older, narrower reports from a single
past session; where they conflict with this file, this file is more current.

## Project snapshot

- Flutter app "Neighbourly": local products/services marketplace on
  Firebase (Firestore, Auth, Storage, Cloud Functions, Cloud Messaging).
- Two separate Flutter entry points, deliberately not linked to each other:
  - `lib/main.dart` — customer storefront app.
  - `lib/main_admin.dart` — admin panel ("Business studio"), fully separate,
    no admin link/button anywhere in the customer app.
- Real Firebase project: `e-commerce-app-a3897`.
- GitHub: `https://github.com/seshu1339-sys/my-project.git`, branch `main`.
- Firebase config for real builds comes from git-ignored local files
  (`firebase-config-android.json`, `firebase-config-web.json`,
  `firebase-config-ios.json`) fed in as `--dart-define` flags — never
  hold the real apiKey/appId in tracked source. See
  `lib/services/firebase_startup.dart`.
- Local Firebase Emulator Suite support exists for dev/testing
  (`lib/services/emulators.dart`, opt-in via `USE_EMULATORS=true` dart-define
  only — off by default in every real build).
- Android release signing is now configured (see latest log entry) —
  `android/app/build.gradle.kts` + `android/key.properties` +
  `android/app/upload-keystore.jks` (all three of the last two/keystore are
  git-ignored; **the keystore and its password exist only on this machine
  and wherever the user has backed them up** — see entry below).

## Standing rules for future sessions

1. Read this file fully, then `git log --oneline -20` and `git status`,
   before making any change.
2. Don't break or rewrite working features. Prefer the smallest correct
   change. Don't "clean up" unrelated code while doing a task.
3. Don't fabricate or guess credentials/secrets. If something needs a real
   credential, real account access, or a production deploy, stop and ask
   the user exactly what's needed rather than guessing.
4. Keep Flutter, Firebase, Android, iOS and Web functionality intact unless
   a task explicitly asks to change one of them.
5. After finishing a task: add a new dated entry at the top of the Log
   below (what changed, files touched, bugs fixed if any, pending items,
   next recommended step), then commit the code and this file together.
6. This environment's own tooling hard-blocks `firebase deploy` and any
   shell command that references the real project ID, even for read-only
   or local-emulator-only purposes, under a safety policy. If a task needs
   an actual deploy, implement/build everything up to that point, then stop
   and hand the user the exact command(s) to run themselves.

## Log (newest first)

### 2026-09-20 — Android release signing configured; signed release APK built

**What changed:** The release build type was signing with the Flutter
debug key (`android/app/build.gradle.kts` had a literal
`// TODO: Add your own signing config`). Generated a real upload keystore
and wired it into Gradle so `flutter build apk --release` now produces a
properly signed APK, falling back to the debug key only if the keystore
files are absent (keeps `flutter run --release` working with no setup).

**Files touched:**
- `android/app/build.gradle.kts` — added keystore-properties loading and a
  `release` `signingConfig` sourced from `android/key.properties`.
- `android/key.properties` (new, git-ignored) — store/key password, alias
  `upload`, path to the keystore.
- `android/app/upload-keystore.jks` (new, git-ignored) — the actual
  keystore, RSA 2048, valid until 2054.

**Bugs fixed:** None (feature/config work, not a bug fix).

**Verification:** Built `app-release.apk` (~55.6 MB) against the real
`e-commerce-app-a3897` Firebase config; confirmed with `apksigner verify
--print-certs` that the shipped APK's certificate fingerprint matches the
new keystore (not the debug key). `flutter analyze` clean.

**⚠️ Action required from the user, not from AI:** back up
`android/app/upload-keystore.jks` and `android/key.properties`
somewhere safe outside this machine. If this app is ever published to
Google Play, every future update must be signed with this exact key —
losing it permanently blocks updates to that listing. The store/key
password was shared with the user directly in chat when this was created;
it is not duplicated here.

**Pending / next recommended step:** Nothing code-side pending from this
task. If the user wants Play Store publication, next steps would be a
Play Console listing plus this same keystore for every future release
build — do not regenerate the keystore for that.

---

### 2026-09-18 — Full live audit: fixed a critical crash, verified checkout end-to-end, verified admin CMS features, pushed to GitHub

This entry summarizes a long live-testing session (Android emulator, Chrome
via Playwright for Web/Admin) that is already fully captured in git history
as individual commits; recorded here as one entry for handoff continuity.

**What changed / bugs fixed:**
- **Critical, previously-undiscovered bug:** `MaterialApp` in `lib/main.dart`
  never registered `flutter_localizations` delegates. Selecting any of the
  app's 23 non-English languages crashed the entire app immediately with
  "No MaterialLocalizations found" on ordinary Material widgets (AppBar,
  NavigationBar, dialogs) — and the crash persisted across restarts because
  the bad language choice is saved to local storage. Fixed by adding the
  `flutter_localizations` dependency and its three standard delegates.
  Verified live by selecting Hindi and confirming previously-crashing
  screens rendered correctly afterward. Commit `cfc6b41`.
- Two other real bugs found via live UI testing and fixed in commit
  `523a3b7`: an admin numeric-field validator wrongly rejected blank
  optional values (e.g. blank `compareAtPrice`), and `Entry.text()` in
  `lib/domain/catalog.dart` didn't apply its fallback for an explicit empty
  string (only for a missing key), so a blank unit showed as `"₹249 /"`
  instead of `"₹249 / each"`.
- `lib/services/emulators.dart`: promoted the dart-define reads to
  top-level `const`s (same fix pattern as elsewhere in the codebase) —
  `bool.fromEnvironment`/`String.fromEnvironment` only reliably fold to
  their dart-define value in a genuine compile-time-constant context; a
  runtime `if` calling them directly can silently evaluate to the default
  on some backends (confirmed on Android AOT).

**Verified working end-to-end (not just code review — actually driven
through the live UI against a local Firebase emulator):**
- Full Android checkout: browse → add to cart → set delivery pincode →
  sign in → enter address → submit → real Cloud Function (`placeOrder`)
  executes → Firestore order document created with correct pricing/
  address/status → cart clears afterward.
- Admin panel (Web, "Business studio"): Promotions, Theme Settings,
  Scrolling Text Settings, Section Customization — each tested by saving a
  real value and confirming it live on the customer web app (a custom
  theme color, a live scrolling ticker message, and hiding the Categories
  section all reflected correctly). Delete flow (confirmation dialog →
  delete → list updates) verified on two content types.

**Known local-environment-only limitation (not an app bug):** the local
Firebase Storage emulator returns `501 Not Implemented` for the resumable
upload that Flutter Web's `firebase_storage` plugin issues from the admin
image-upload button. The app's own upload code
(`ref.putData(...)` in `lib/data/store.dart`) is standard and correct;
this reproduced identically after a full clean emulator restart, so it's a
known gap in the emulator, not something to "fix" in app code. Uploads
against the real production Storage bucket are expected to work normally.

**Also done:** Pushed all local commits to `origin/main` (repo previously
only had the initial commit on GitHub despite 14 local commits of real
work). GitHub is now the source of truth alongside this machine.

**Pending / next recommended step:**
1. Production deployment (`firebase deploy`) still has never been run —
   this environment's own tooling refuses to run it under any
   circumstance (see Standing Rule 6). The user needs to run it
   themselves; deploy steps are documented in
   `docs/authentication-deployment.md`.
2. Real push-notification delivery has not been verified on a real
   device/real Firebase project (no FCM emulator exists locally).
3. iOS build/signing is out of scope (no macOS available in this
   environment).

---

### Earlier history (pre-2026-09-18, see `git log` for full detail)

Auth migrated from SMS/PIN to email/password + email-link (`87c54a9`);
admin panel fully separated into its own app/entry point (`d76b5b9`);
delivery/service charges added as a real pricing + checkout feature
(`10bf936`); one-to-one order-status push notifications added (`a60c2aa`);
responsive layout customization system added (`22819e3`); wishlist/saved-
card/language sync bug fixed (`bdc525e`). See `docs/notifications.md`,
`docs/authentication-deployment.md`, `docs/production-verification.md`,
`docs/responsive-validation.md`, and `docs/home-ui.md` for the detailed
narrative reports from that period. Treat those as historical snapshots,
not current status — this file's log is authoritative for "what's true
right now."
