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

## Exact production actions proposed

Project: **e-commerce-app-a3897**.

1. Authentication configuration: enable email-link sign-in by setting `signIn.email.enabled=true` and `signIn.email.passwordRequired=false`. Keep Phone authentication disabled. Email/password remains available. Preserve authorized domains and all unrelated project settings.
2. Functions in `us-central1`: update **pinLogin**, **setPin**, and **placeOrder** only. The first two reject retired SMS/PIN authentication; checkout additionally requires `email_verified=true`. Existing authoritative pricing, stock transaction and idempotency logic stay intact.
3. Firestore rules: publish `firestore.rules`, requiring verified email for authenticated private operations and admin writes while preserving public catalog browsing.
4. Storage rules: publish `storage.rules`, requiring verified email as well as the existing admin claim for catalog uploads/deletion.
5. Firebase Hosting: publish **build/web** to **https://e-commerce-app-a3897.web.app**. Hosting publishes the entire current local app, including the previously completed responsive work and the new authentication screens; the old hosted bundle differs from it. No homepage redesign was added in this migration.
6. Verify provider settings, hosted bundle hash, safe callable rejection behavior and the hosted authentication UI. Real email delivery/sign-in needs an owner-supplied address and interaction with its inbox.

Reviewed `build/web/main.dart.js` SHA-256:
`AA6E3313B2DF2AD9B2B37459EC184020CD012F790ADCBED181102131680E713D`

Commands prepared, **not executed**:

```powershell
node scripts/firebase-setup.cjs configure-email-link
firebase.cmd deploy --only "functions:pinLogin,functions:setPin,functions:placeOrder,firestore:rules,storage,hosting" --project e-commerce-app-a3897 --non-interactive
node scripts/firebase-smoke.cjs
```

This scope does not deploy notification functions, change IAM/billing, create accounts/orders, modify catalog records, or grant admin access.

## Current production state and approval reason

The earlier authorized provider update succeeded: **Email/Password is enabled; Phone is disabled**. Email-link mode has not yet been enabled. The attempted combined app/functions/rules deployment was rejected before execution by automatic approval review because it considered those persistent production changes broader than the authentication request authorized. No workaround or split deployment was attempted.

Consequently, the hosted client still has its old SMS/PIN interface while the Phone provider is disabled. Live sign-in is not ready until the coordinated migration above is approved and published. The last audit found no registered Auth users, but that is not a substitute for deployment approval.

Approval is requested for exactly the six actions above. After approval and publication, the owner can use email-link sign-in or register with email/password and verify their inbox. Administrator access will be assigned only to an explicitly identified, enabled, verified-email account; `scripts/firebase-setup.cjs grant-email-owner EMAIL` and `functions/set-admin.js PROJECT UID` enforce verification.
