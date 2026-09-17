# Neighbourly

A Flutter customer marketplace and business admin panel for responsive web, Android and iOS.

## Run

```powershell
./scripts/flutter.ps1 pub get
./scripts/flutter.ps1 run -d chrome
```

Without Firebase build configuration the app runs a labelled demo. Demo catalog edits persist on the current device; demo checkout never creates real orders. The wrapper locates the installed Flutter SDK and GitHub Desktop Git. Standard `flutter` commands also work with a healthy SDK command path.

## Authentication migration

The current client supports email/password with email verification, password reset, and passwordless email links. See [the tested migration and exact deployment scope](docs/authentication-deployment.md) before using production: the provider configuration has changed, but the combined client/functions/rules publication awaits approval. Older SMS/PIN descriptions below describe the previous release.

## Included

- Responsive storefront, animated ticker, clickable auto-advancing promotions, nested categories, product/service filters, text search, image gallery, location pricing, cart and order-request checkout.
- GPS/manual pincode, per-shop service radius, nearby shops, OpenStreetMap pins, Google Maps routes and shop catalogs.
- Email/password and passwordless email-link authentication; profile, logout, orders and reviews.
- A separate admin studio app (not part of the customer app) with forms for products, services, categories, shops, coordinates, radii, pincode prices, image uploads/URLs, scheduled promotions, layout/theme customization, order queue and status changes, and business identity. Hide/unpublish avoids destructive deletion.
- Voice/image provider interfaces in `lib/services/search.dart`. Recognition providers are not configured; the UI reports this explicitly.

## Firebase

Discovered project: `e-commerce-app-a3897`. Local platform client configurations are excluded from Git. `config/firebase.example.json` documents the required build defines.

```powershell
./scripts/flutter.ps1 run -d chrome --dart-define-from-file=firebase-config-web.json
./scripts/flutter.ps1 build web --dart-define-from-file=firebase-config-web.json
./scripts/flutter.ps1 build apk --debug --dart-define-from-file=firebase-config-android.json
npm.cmd ci --prefix functions
firebase.cmd deploy --only firestore:rules,firestore:indexes,storage,functions --project e-commerce-app-a3897
firebase.cmd deploy --only hosting --project e-commerce-app-a3897
```

Cloud Functions and Storage require suitable billing/service configuration. Enable Authentication's Phone provider, SMS regions and authorized web domains. Android requires signing SHA fingerprints; iOS requires APNs and phone-auth callback configuration. Verify actual SMS sign-in on configured devices before launch. Firebase client keys identify the application; never place service-account, signing or payment secrets in Flutter.

For the current project, Phone authentication and India SMS delivery are configured, Blaze billing is enabled, and Storage is provisioned in Mumbai. The live website is https://e-commerce-app-a3897.web.app. The setup helper uses the already signed-in Firebase CLI without exporting credentials:

```powershell
node scripts/firebase-setup.cjs inspect
# Idempotently check/create Storage (requires billing):
node scripts/firebase-setup.cjs create-storage
```

Storage creation uses `asia-south1`, matching the existing database. This helper uses the installed Firebase CLI internals (validated with CLI 15.30.0); on another machine set `FIREBASE_TOOLS_LIB` to its `firebase-tools/lib` directory. It does not enable billing or submit payment information.

Use Node 22 / npm 10 for backend installation, matching Cloud Build. The lockfile is validated with npm 10.9.4. On this Windows machine, set `FUNCTIONS_DISCOVERY_TIMEOUT=60` when deploying to accommodate local module loading. `node scripts/firebase-smoke.cjs` verifies the hosted bundle and negative authentication checks without creating data.

All three Functions are deployed with owner-approved public HTTP invocation; handler-level PIN/SMS/authentication checks remain required. Live smoke checks pass for hosting and all three callable rejection guards. The runtime's self-signing permission is configured. If invocation IAM needs repair, the explicitly authorized operator command `node scripts/firebase-setup.cjs configure-invokers` preserves existing bindings and verifies access for only these three services. See `BUILD_STATUS.md` for remaining verification.

### Customer alerts

Signed-in item views and opt-in Firebase Messaging alerts are implemented, including a one-account-to-one-account order-status alert (`notifyOrderStatus`) sent only to the customer whose order changed. See [notification setup and delivery behavior](docs/notifications.md) for the web VAPID key, iOS APNs setup, scheduling and device verification.

### Administrator

The admin studio is a **separate app**, not reachable from the customer app at all — there is no admin link, button or route inside the customer build. It is a second Flutter entry point, `lib/main_admin.dart`, built and deployed independently:

```powershell
./scripts/flutter.ps1 build web -t lib/main_admin.dart -o build/admin_web --dart-define-from-file=firebase-config-web.json
```

Deploy `build/admin_web` to its own Firebase Hosting site/target (not yet configured or deployed) so it gets its own URL, separate from the customer site. Sign in to the intended owner's account with email and password (verify the email first), then grant that existing Auth UID the admin claim from a trusted environment with Application Default Credentials:

```powershell
node functions/set-admin.js e-commerce-app-a3897 EXISTING_USER_UID
```

Sign out and back in (or reload the admin app) to refresh claims. Customers cannot elevate their role, and the admin app itself refuses any signed-in account without the claim. Add business settings, shops, categories, products and promotions in the studio. Demo data is never automatically written to the live database.

## Architecture

`lib/domain`: catalog models, fixtures, prices and distance calculations. `lib/data`: reactive repository, Firestore, demo persistence, authentication, Storage and checkout. `lib/services`: search contracts. `lib/ui`: storefront, account, shops, products, cart and admin.

| Path | Purpose | Write authority |
| --- | --- | --- |
| `products/{id}` | Product/service, pincode prices, stock, images, category/shop | Admin; checkout updates stock |
| `categories/{id}` | Name, parentId, order | Admin |
| `shops/{id}` | Address, coordinates, pincode, radius | Admin |
| `promotions/{id}` | Placement, target, dimensions, order, start/end | Admin |
| `settings/business` | Identity and default radius | Admin |
| `users/{uid}` | Display name | Owner |
| `products/{id}/reviews/{uid}` | One editable review per customer | Owner, validated |
| `orders/{id}` | Server-priced snapshot (lines, subtotal, deliveryFee, total) and status | Functions create; admin changes status; Functions restore stock on cancellation |
| `_pins/{uid}` | Salted scrypt hashes | Functions only |
| `_rateLimits/{digest}` | Transactional request limits | Functions only |
| Storage `catalog/{file}` | JPEG/PNG/WebP under 5 MB | Admin |

Public catalog documents, including hidden/scheduled records, are readable. Scheduling is a presentation control, not confidentiality. Never put private information in catalog documents.

`pinLogin` and `setPin` are retired: they reject every call with an explicit error instead of issuing tokens, kept only so the old callable URLs fail loudly rather than disappear. `placeOrder` requires a verified email and checks identity, stock and server prices transactionally; deterministic request IDs prevent duplicate submission after network retries. It also applies `settings/business`'s optional flat `deliveryFee` (waived once the order subtotal reaches `freeDeliveryAbove`), authoritatively, on the server — the client's own display of it is an estimate only. Checkout creates a request, not a payment transaction. `reconcileCancelledOrderStock` watches `orders/{id}` and, the first time an order's status becomes `cancelled`, transactionally restores each line's quantity to `products/{id}.stock`; a `stockRestored` flag makes this idempotent if status is toggled again. `notifyOrderStatus` sends a push notification to only the customer whose order just changed status.

## Verify

```powershell
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test
npm.cmd test --prefix functions
firebase.cmd emulators:exec --only firestore --project demo-neighbourly "node --test functions/rules.test.js"
./scripts/flutter.ps1 build web
./scripts/flutter.ps1 build apk --debug
```

Rules tests explicitly skip without an emulator. Domain tests cover hashes and authoritative pricing/stock. Flutter tests cover scheduling, radius, pricing, persistence, responsive layouts, search and cart navigation.

## Release boundaries

Online payments/refunds, tax, zone/distance-based delivery pricing, dispatch and recognition providers remain integrations; only a flat, optional business-wide delivery/service fee is implemented. Push notifications (price drops, new offers, order status) are implemented in code; real device delivery still needs the web VAPID key and, for iOS, APNs/Xcode setup. Service orders are requests, not appointment calendars. Reviews are authenticated, not purchase-verified. Cancelling an order automatically restores its reserved stock exactly once (`reconcileCancelledOrderStock`); this does not retroactively fix orders cancelled before that function was deployed. Each catalog collection's live listener is capped at 2,000 documents as a safety rail against runaway reads/cost, with a visible "showing the first 2,000 items" notice if a collection ever hits it; this is not paginated browsing, and a catalog that outgrows the cap needs a real paginated/server-searched catalog, a larger change. Further abuse controls are still needed.

Android debug APKs are for review. The starter release signing uses the debug key and is unsuitable for Play Store publication. iOS requires macOS/Xcode, signing, APNs and physical-device testing. Replace public OpenStreetMap tiles with a suitable production provider at scale.
