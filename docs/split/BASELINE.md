# Split into 4 apps -- Phase 0 baseline (2026-10-21)

Branch `split-apps`, from `main` at ccd7e8e. Rollback point: git tag `pre-split-2026-10-21`.
Nothing on this branch is deployed or pushed until the owner says so.

## Tests before any change
- Flutter: 377 pass. `flutter analyze`: 12 infos (all older, none new).
- Backend (emulators): 81/81 pass.

## What is live now (fingerprint = first 16 hex of sha256 of main.dart.js)
| Site | HTTP | main.dart.js |
|---|---|---|
| e-commerce-app-a3897.web.app (customer) | 200 | 5b023cb4be4e7b27 |
| e-commerce-app-a3897-admin.web.app | 200 | bf3583ed953709ef |
| e-commerce-app-a3897-vendor.web.app | 200 | 66a1a9e27eb8f904 |
| e-commerce-app-a3897-field.web.app | 200 | 564f01ca277f3335 |
| locamarket.in (Hostinger, older build from 2026-10-21 morning) | 200 | ca45881cba57a690 |

Functions: all earlier Quick Add functions are live; `setQuickShopLocation` and `saveQuickItems` (commit ccd7e8e) are NOT
deployed yet (the owner must run `firebase deploy --only functions`). Local commit ccd7e8e is not pushed.

## Rules for this work
- Do not remove or rename any existing option/setting/page. The customer web app keeps the `/jyothi9` admin route until the
  owner says to remove it (before the customer app goes to the Play Store).
- No deploy, no push, no data change without the owner's explicit OK.
- Old vendor/field websites stay until the Android apps exist, then become "download the app" pages.

## Android identity today
- applicationId `in.locamarket.locamark`, label "Neighbourly", one `google-services.json` (also lists com.example.ecommerce_app).
- Entrypoints already exist: lib/main.dart (customer), main_admin.dart, main_vendor.dart, main_field.dart.

## Targets
| App | Platform | Name | Package |
|---|---|---|---|
| Customer | Android + locamarket.in | Loca Market | in.locamarket.locamark |
| Admin | web only | Business Studio | - |
| Vendor | Android | V Loca Market | in.locamarket.vendor |
| Staff | Android | S Loca Market | in.locamarket.staff |
