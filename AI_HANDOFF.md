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

### 2026-09-20 — Site/ad analytics, product-interest counts, price-alert admin controls

**Audit first (what already existed, reused):** email-link auth, vendor photos,
Pending Approval, per-vendor fee, `notifyPriceDrop` + `send()` + the
`_notificationDeliveries` duplicate claim, `notificationSubscribers`, push tokens,
`products/{id}/viewers` (interest), per-promotion scroll speed/stop controls.
**Missing and added:** visitor/ad analytics, view *counts*, an admin eligible-customer
list, automatic/manual alert controls, per-price dedupe.

**Added:** `trackEvent` callable + `functions/analytics.js` (anonymous device id,
aggregate counters only, sharded, unique counts via hashed expiring markers in
`analyticsSeen` - enable a Firestore TTL policy on `analyticsSeen.expiresAt`);
collections `analyticsDaily|Totals|Ads` (admin-read, server-write). Client:
`lib/services/analytics.dart` (customer app only). Impressions count only when an
ad is >=50% on screen; clicks per tap; `?ad=<promotionId>` credits visits to an ad.
`trackItemView` now increments `viewCount` (30 s throttle; rules allow +1 only).
`notifications.js`: dedupe key `priceDrop:{product}:{pincode}:{price}` (7-day
re-alert window), setting `priceDropAutoEnabled` (blank = on), callables
`priceAlertAudience` / `sendPriceDropAlerts` (admin only). Admin > Insights screen.

**Verification:** analyze clean, Flutter 48/48, backend 29/29 (emulators, none skipped). Live: web +
Android tracking, interest counts, alerts (dry-run), ad scroll, fees, plus regression of vendor
onboarding, fee/payment, shop verification, complaints, admin sections. Nothing deployed/committed.

**Testing notes:** emulators cannot deliver FCM. `functions/.env.local`
(`PUSH_DRY_RUN=true`, git-ignored, emulator-only) records would-be pushes in
`_pushDryRun`. Real push delivery is NOT verified. A base-price edit does not alert
customers who have a pincode-specific price (existing, intended). Backend tests now
run one file at a time (`--test-concurrency=1`) because they share an emulator.

### 2026-09-20 — Vendor onboarding: email link -> full registration + 2 photos -> admin review -> unlock

**Flow:** Vendor App login now leads with the *existing* Email Link auth
(`EmailLinkPage`, now takes an optional `continueUrl` so the vendor site gets
its own link; customer default unchanged). Only a verified email sees the
registration form (owner name, phone, shop name, category, address, pincode,
description + two mandatory photos). Photos upload to separate private Storage
paths `vendorApplications/{uid}/vendorPhoto|shopPhoto`. `registerVendor` (server)
re-validates every field and checks both objects exist; status becomes `pending`
("Pending Approval" screen). Admin tile shows both photos + all details;
`approveVendor` refuses to approve without both photos. Approval (fee OFF, or fee
confirmed) unlocks the dashboard: add product/material with photo, my products
(price / stock / photo), orders with confirm/fulfil/cancel. Same data model
(`vendorApplications`, `vendors`, `vendorChanges`); no new auth mode.

**Security changes:** `submitVendorChange` now needs `vendors.status=='approved'`
(GPS `verified` is no longer required for business features, still required for
purchase-code redemption); vendors may only change items they own or that belong
to their own shop; new types `newProduct`/`stock`; all values validated
(`domain.js`). `storage.rules`: private application photos (owner writes only
before submit/after rejection; owner+admin read), `vendorProducts/{uid}` writable
only by an approved vendor. Resubmission clears the previous decision fields.
New product/price/stock changes still follow the existing policy: held for admin
approval unless Auto-publish is on.

**Tests:** `functions/vendor-storage.test.js` (rules), `domain.test.js`,
`test/vendor_test.dart`. Live: web + Android + 70 API access checks (scratchpad).

**Not deployed.** Deploy needs Storage rules + Functions + hosting (user-run).
Unverified in production: Admin SDK default bucket in Functions, Storage CORS
for admin photo previews on web, Storage cross-service rules permission.
**Android note:** no deep links, so the emailed link opens the customer site;
the vendor pastes the link into the app (same fallback as customers).

### 2026-09-20 — Live end-to-end test (Android + Web) and 4 bug fixes

**What was done:** Ran customer, vendor and admin apps for real against the
local Firebase emulators (project `demo-neighbourly-e2e`; nothing touched
production). Web driven with Playwright + system Chrome (Flutter semantics
enabled), Android driven on the `Medium_Phone` AVD via adb/uiautomator. Covered
customer register/login/search/category/cart/checkout (direct + COD), vendor
registration -> admin review -> fee ON/OFF -> payment submit/reject/confirm,
vendor change publishing, complaints, admin sections, responsive 390/768/1440.

**Bugs fixed (uncommitted):**
1. Admin settings form saves toggles as text ("true"), backend required boolean
   `true` -> COD, platform collection and vendor auto-publish were silently
   ignored server-side (customer was offered COD, order rejected). Fixed in
   `functions/domain.js` (`flagOn`/`flagOff`) + `functions/index.js`; test added.
2. Customer "Open a complaint" could never succeed (server requires an order,
   dialog sent none). Dialog now has an order picker (`lib/ui/account.dart`).
3. Vendor App "Orders" count queried a `vendorId` field orders don't have (always
   0). Now queries `shopIds array-contains <vendor shopId>` (`lib/ui/vendor.dart`).
4. Vendor payment screen never showed the admin's review note (the only place
   the admin can give payment instructions). Now shown as "Administrator note".

**Open / not fixed:** Vendor App has no create-account screen (vendors must
register in the customer app first); vendor application collects no
email/phone; Vendor App has no order status or complaint reply UI; register form
places the email-link button between Password and Confirm; after a rejected fee
payment the reference field keeps the old text.

**Test-harness notes:** Android emulator mode needs an API key shaped `AIza...`
and a full `FIREBASE_AUTH_DOMAIN` (fake keys make Installations/Auth throw) -
this was the earlier "Android PERMISSION_DENIED" mystery, not an app bug. Web
session persistence across reload cannot be checked with the emulator (SDK
does the persisted-user lookup before `useAuthEmulator` is applied).
`functions` email-flow tests hard-code project `demo-neighbourly`; run them with
`firebase emulators:exec --project demo-neighbourly`.

**Verification:** `flutter analyze` clean, `flutter test` 43/43, backend 21/21
with emulators (0 skipped). No deployment performed.

### 2026-09-20 — Added post-review vendor fee workflow

**What changed:** Updated only the vendor registration workflow. Customer
registration and checkout have no registration fee. Admin now sees the full
vendor application details in an expandable review record and chooses Fee
Required ON/OFF. When ON, the admin enters any positive custom amount (for
example 500, 750, 1000); when OFF, the vendor proceeds without payment.

**Review-gated payment:** Admin approval transitions a fee-required vendor to
`payment_required`; only that post-review status renders the Vendor App payment
screen. The vendor submits a payment reference, then Admin confirms or rejects
it. Only confirmation creates the approved vendor record. Fee-off approvals
create the approved vendor immediately. Re-submission cannot bypass an active
application or fee decision.

**Files touched:** `functions/index.js`, `functions/domain.js` and tests,
`lib/data/store.dart`, `lib/ui/vendor.dart`, and `lib/ui/admin.dart`.

**Verification:** `flutter analyze`, `flutter test`, Functions syntax checks,
Functions unit tests, Firebase JSON parsing, and `git diff --check` pass.

**Pending:** No deployment was performed. This workflow records fee payment
references for admin confirmation; no external vendor-fee gateway was added.

**Next recommended step:** Test one fee-OFF and one fee-ON application through
the local emulator, including admin rejection and payment confirmation.

### 2026-09-20 — Added configurable payment policy and complaint review

**What changed:** Added future-ready payment policy settings to the existing
Admin business profile: customer pays vendor directly, cash on delivery, and
platform-collected payment with vendor settlement. Direct vendor payment is
the backward-compatible default; cash on delivery and platform collection are
opt-in toggles. Checkout now sends and stores the selected method and a
corresponding payment status. Platform collection is configuration-ready only;
no platform gateway or settlement is enabled or deployed.

**Complaints:** Added secure callable-backed complaint cases with customer,
vendor, and order/product context; full message history; participant replies;
admin status transitions (`open`, `in_review`, `resolved`, `closed`); and
resolution notes. Customer account UI can open and track complaints, and the
central Admin Panel can inspect histories and review them. Firestore rules
allow history reads only to the participants or admins; clients cannot write
cases or messages directly.

**Files touched:** `functions/index.js`, `functions/domain.js` and tests,
`firestore.rules`, `lib/data/store.dart`, customer cart/account UI, and the
existing admin UI/settings editor.

**Verification:** `flutter analyze`, `flutter test`, Functions syntax checks,
Functions unit tests, Firebase JSON parsing, and `git diff --check` pass.

**Pending:** No deployment was performed as requested. Payment gateway,
platform settlement, refunds, and payout reconciliation remain deliberately
disabled. Vendor-facing complaint reply UI can be expanded in a follow-up;
the callable and secure history model are in place.

**Next recommended step:** Exercise payment toggles and complaint history
against the local Firebase Emulator Suite, then plan the future platform
payment provider and settlement ledger independently of order checkout.

### 2026-09-20 — Added separate vendor app and secure vendor publishing workflow

**What changed:** Extended the existing customer/admin Firebase system with a
separate Vendor App entry point (`lib/main_vendor.dart`) and vendor workspace.
Vendor registration and approval, admin shop GPS verification, vendor product/
price/shop change submissions, auto-publish policy, pending audit records with
old/new values, rejection reasons, vendor order status updates, and vendor
change history are now backed by callable Cloud Functions. Firebase Hosting
has a separate `vendor` target for `build/vendor_web`.

**Purchase and ratings security:** Customers can request a five-minute,
single-use purchase code only for a fulfilled order and their current GPS
location. Vendors redeem it only while inside the admin-verified shop radius;
the server transaction consumes it exactly once. Review writes are now
callable-only, require a verified purchase of the exact product, prevent a
second rating by the same customer, and flag rapid review patterns for admin
inspection. Direct Firestore review writes remain denied by rules.

**Files touched:** `functions/index.js`, `functions/domain.js`, backend tests,
`firestore.rules`, `firebase.json`, `lib/data/store.dart`, customer account and
review UI, `lib/main_vendor.dart`, `lib/ui/vendor.dart`, and the existing admin
moderation UI.

**Verification:** `flutter analyze`, `flutter test`, Functions syntax checks,
Functions unit tests, Firebase JSON parsing, and `git diff --check` pass.

**Pending:** Deploying Functions, Firestore rules, and the three Hosting
targets remains a user-run production action under the repository safety rule.
Real FCM and production payment/delivery verification remain pending. The
vendor UI currently provides the core registration, publishing, order status,
and purchase verification workflows; complaints and payment settlement remain
follow-up modules.

**Next recommended step:** Run the local emulator integration tests with the
new callable flows, then deploy Functions/rules and build the vendor target
with the same Firebase dart-defines used by the customer/admin builds.

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
