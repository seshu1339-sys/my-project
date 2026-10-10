# Email authentication migration — approval scope

## Ready locally

The client supports email/password registration and sign-in, verification resend/check, password reset, and passwordless email-link sign-in. Existing homepage styling and layout are preserved.

Passwordless flow: Account → Sign in with an email link → enter email → Send sign-in link. Incoming web links open a confirmation page. The last successfully sent-to address is remembered on that device, but the email is never accepted from URL parameters. Another device asks for the address again. Invalid/expired/used links show an actionable error. Successful completion refreshes the token, clears the remembered address and removes the action URL from browser history. Native clients can paste the complete link using “I already have a sign-in link”; automatic Android/iOS universal-link routing is not configured by this change.

Email-link sign-in also verifies ownership of the address. The backend and rules require a verified-email claim for protected operations. SMS/PIN function URLs remain deployed endpoints after migration, but return an explicit retired-method error instead of issuing custom tokens. No existing data or users are deleted. See [Firebase email-link documentation](https://firebase.google.com/docs/auth/flutter/email-link-auth).

## Verification completed

- Flutter analysis: no issues.
- Full Flutter regression suite after the email/password migration: 35 passed.
- Final focused client tests, including passwordless and cross-device/error states: 4 passed.
- Backend tests: 8 passed; the rules test skipped by that command was run separately and passed in the Firestore emulator.
- Firebase Auth emulator: 2 end-to-end tests passed for registration/verification/reset and passwordless sign-in. Wrong-email and replay attempts are rejected.
- Firebase-connected web build: succeeded.
- Local installed Chrome: 8 checks passed; no captured JavaScript page errors. Includes widths 390/768/1440, removal of SMS/PIN fields, passwordless route, invalid email/link handling, and incoming-link confirmation that ignores an untrusted URL email. Screenshots were visually reviewed.
- Real inbox delivery, live account creation, live checkout and live admin writes were not performed.

Artifacts: `build/email-analysis.log`, `build/email-flutter-tests.log`, `build/email-link-widget-tests.log`, `build/email-backend-tests.log`, `build/email-rules-tests.log`, `build/email-flow-emulator.log`, `build/email-web-build.log`, and `build/browser-check/email-link-results.json`.

## Exact production actions proposed (updated 2026-09-17, post admin-panel separation)

Project: **e-commerce-app-a3897**. Since this doc was first written, the admin studio went through two phases: briefly a second, separate app (`lib/main_admin.dart`), then (commit `d4db584`) deliberately reverted so the admin route (the hidden `/jyothi9`-style path in `lib/main.dart`) shares the exact same compiled bundle as the customer app — specifically so admin access gets the same password+email-OTP two-factor flow, which the old separate `main_admin.dart` build never had. `lib/main_admin.dart` still exists in the repo but is dead code, not part of any build command below. The admin Hosting target now gets its distinct identity (a PWA installable as "Locamarket Control" on iPhone) via `scripts/build-admin-web.ps1`, which runs *after* the one `flutter build web` and overlays only static `index.html`/`manifest.json`/icon files from `web_admin_overlay/` onto a copy of `build/web` — never a second Flutter compile, so the OTP gate stays identical either way. `placeOrder`/`quote()` also gained an optional delivery/service fee, and two new notification/stock functions were added. The scope below supersedes the original six-action list.

1. One-time Hosting target setup (see **Step-by-step deploy commands** below) so `firebase.json`'s two hosting configs (`customer`, `admin`) resolve to real sites.
2. Authentication configuration: enable email-link sign-in by setting `signIn.email.enabled=true` and `signIn.email.passwordRequired=false`. Phone stays disabled. Email/password remains available. Preserves authorized domains and all unrelated project settings.
3. Functions in `us-central1`/`asia-south1`: **pinLogin** and **setPin** reject retired SMS/PIN authentication; **placeOrder** requires `email_verified=true` and now also applies `settings/business`'s optional delivery/service fee; **reconcileCancelledOrderStock** and **notifyOrderStatus** are new (stock restore on cancellation, one-to-one order-status push). `notifyPriceDrop`/`notifyNewOffers` are unchanged.
4. Firestore rules: publish `firestore.rules` — verified email for authenticated private operations and admin writes, plus the widened (still validated) `users/{uid}` field set for wishlist/payment-card/language sync; public catalog browsing unchanged.
5. Storage rules: publish `storage.rules` — verified email plus the existing admin claim for catalog uploads/deletion.
6. Firebase Hosting: publish **build/web** to the customer site and **build/admin_web** (the same compiled app, with `scripts/build-admin-web.ps1`'s PWA-identity overlay applied) to the admin site. The admin route is reached only via the hidden path inside the one shared bundle, gated by the password+OTP flow — not a separate, less-secure app.
7. Web push: `FIREBASE_VAPID_KEY` is now set in the local `firebase-config-web.json` build-define file (owner-supplied), so it will be embedded in the customer build from this point on.
8. Verify: hosted bundle hash, safe callable rejection behavior, both hosting sites serving, and the admin site's sign-in gate.

This scope does not change IAM/billing, create customer accounts/orders, or modify catalog records. Granting the admin claim is a separate, explicit step (below) gated on the owner actually registering and verifying their email first — it cannot happen before hosting is live, since the currently-deployed customer site still has the old SMS/PIN UI.

## Step-by-step deploy commands

Run these from the project root, in order. Each one only does what it says; nothing here grants admin access or touches billing/IAM.

```powershell
# 1. One-time: point the two hosting configs in firebase.json at real sites.
#    "customer" reuses the EXISTING live site (same ID as the project) — this does not create anything new or move your current site.
firebase target:apply hosting customer e-commerce-app-a3897 --project e-commerce-app-a3897
#    "admin" needs a brand-new site, created once:
firebase hosting:sites:create e-commerce-app-a3897-admin --project e-commerce-app-a3897
firebase target:apply hosting admin e-commerce-app-a3897-admin --project e-commerce-app-a3897

# 2. Enable email-link sign-in (email/password was already enabled earlier; this adds passwordless).
node scripts/firebase-setup.cjs configure-email-link

# 3. Build the one web app (customer + the hidden admin route share this build),
# with the live Firebase config (includes the VAPID key for push), then overlay
# the admin PWA identity on a copy of it — never a second Flutter compile.
./scripts/flutter.ps1 build web --dart-define-from-file=firebase-config-web.json
./scripts/build-admin-web.ps1

# 4. Deploy backend: all functions (including the two new ones), Firestore rules, Storage rules.
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
firebase deploy --only functions,firestore:rules,storage --project e-commerce-app-a3897 --non-interactive

# 5. Deploy both hosting sites.
firebase deploy --only hosting --project e-commerce-app-a3897 --non-interactive

# 6. Verify.
node scripts/firebase-smoke.cjs
```

**Only after step 6 succeeds:** open the now-live customer site, register with the intended owner email, and click the verification link sent to that inbox. Only then run:

```powershell
node scripts/firebase-setup.cjs grant-email-owner OWNER_EMAIL_HERE
```

This fails on purpose if that email hasn't registered and verified yet — it never creates or guesses an account. Once it succeeds, sign out and back in (or just reload) on the **admin** site — `https://e-commerce-app-a3897-admin.web.app` — to pick up the refreshed claim.
