# Neighbourly

A Flutter customer marketplace and business admin panel for responsive web, Android and iOS.

## Run

```powershell
./scripts/flutter.ps1 pub get
./scripts/flutter.ps1 run -d chrome
```

Without Firebase build configuration the app runs a labelled demo. Demo catalog edits persist on the current device; demo checkout never creates real orders. The wrapper locates the installed Flutter SDK and GitHub Desktop Git. Standard `flutter` commands also work with a healthy SDK command path.

## Included

- Responsive storefront, animated ticker, clickable auto-advancing promotions, nested categories, product/service filters, text search, image gallery, location pricing, cart and order-request checkout.
- GPS/manual pincode, per-shop service radius, nearby shops, OpenStreetMap pins, Google Maps routes and shop catalogs.
- Phone + six-digit PIN authentication; SMS registration/recovery; profile, logout, orders and reviews.
- Business studio forms for products, services, categories, shops, coordinates, radii, pincode prices, image uploads/URLs, scheduled promotions, order and business identity. Hide/unpublish avoids destructive deletion.
- Administrator order queue and status changes.
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

### Administrator

Sign in to the intended owner's account using SMS, then grant that existing Auth UID the admin claim from a trusted environment with Application Default Credentials:

```powershell
node functions/set-admin.js e-commerce-app-a3897 EXISTING_USER_UID
```

Sign out and back in to refresh claims. Customers cannot elevate their role. The owner phone/UID must be explicitly identified. Add business settings, shops, categories, products and promotions in the studio. Demo data is never automatically written to the live database.

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
| `orders/{id}` | Server-priced snapshot and status | Functions create; admin changes status |
| `_pins/{uid}` | Salted scrypt hashes | Functions only |
| `_rateLimits/{digest}` | Transactional request limits | Functions only |
| Storage `catalog/{file}` | JPEG/PNG/WebP under 5 MB | Admin |

Public catalog documents, including hidden/scheduled records, are readable. Scheduling is a presentation control, not confidentiality. Never put private information in catalog documents.

`pinLogin` rate-limits phone/IP attempts and issues a Firebase custom token after hash verification. `setPin` requires recent SMS authentication and revokes refresh tokens. `placeOrder` checks identity, stock and server prices transactionally; deterministic request IDs prevent duplicate submission after network retries. Checkout creates a request, not a payment transaction.

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

Online payments/refunds, tax/delivery policies, dispatch, push notifications and recognition providers remain integrations. Service orders are requests, not appointment calendars. Reviews are authenticated, not purchase-verified. Cancelled orders currently require manual stock reconciliation. Large catalogs need pagination and further abuse controls.

Android debug APKs are for review. The starter release signing uses the debug key and is unsuitable for Play Store publication. iOS requires macOS/Xcode, signing, APNs and physical-device testing. Replace public OpenStreetMap tiles with a suitable production provider at scale.
