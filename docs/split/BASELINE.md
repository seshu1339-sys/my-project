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

## Phase 1 (done on branch split-apps): three Android flavors
- `android/app/build.gradle.kts`: flavors `customer` (in.locamarket.locamark, "Loca Market"), `vendor` (in.locamarket.vendor,
  "V Loca Market"), `staff` (in.locamarket.staff, "S Loca Market"); `pubspec.yaml` `default-flavor: customer`.
- Firebase: two new Android apps registered in project e-commerce-app-a3897 by CLI (vendor 1:462582150390:android:da5046af1a0f52888d28d7,
  staff 1:462582150390:android:229235cd6563ea778d28d7), each with the upload-key SHA-1 and SHA-256. The app is configured through
  dart-defines, so each flavor has its own `firebase-config-android-<flavor>.json` (git-ignored, same keys, different FIREBASE_APP_ID).
- Build one: `flutter build apk --flavor vendor -t lib/main_vendor.dart --dart-define-from-file=firebase-config-android-vendor.json`
  (customer: default `-t lib/main.dart` + `firebase-config-android.json`; staff: `--flavor staff -t lib/main_field.dart` + `...-staff.json`).
- Customer icon from the supplied logo is in `android/app/src/customer/res`. Vendor/staff icons wait for the owner's approval of the
  "V"/"S" designs (then: node icons script -> `src/vendor/res`, `src/staff/res`).
- Checked with aapt2: package names and labels are right. Vendor and staff builds contain no admin route; the customer build
  still contains `/jyothi9` (kept until the owner says to remove it, before the Play Store release).

## Phase 1 emulator test (Android emulator "Medium_Phone", debug APKs of all three flavors installed side by side)
- Customer: opens the storefront. Vendor: "Vendor studio" sign-in. Staff: "Field Assistant" / "Staff sign-in". Packages and labels correct.
- Found and fixed a bug that predates this work: `buildAppTheme` scaled the theme font size (live theme has fontSize 12) with
  `TextTheme.apply(fontSizeFactor:)`, which asserts on styles without a size -> a red error screen in debug builds of the Android
  customer app (release builds skip the assert and leave those styles alone, which is what `_scaled` now does explicitly, so the
  look of the live site does not change). Regression test: test/app_theme_test.dart.

## Phase 2: role security (done on branch split-apps)
- Vendor and staff launcher icons (approved "V" and "S" designs) are in `android/app/src/{vendor,staff}/res`; logos in `assets/branding/`.
- `scripts/check-app-isolation.cjs`: after building the three RELEASE APKs it proves each app contains only its own screens
  (all 28 checks pass): customer has no admin / vendor / staff screens or admin callables; vendor has no staff, admin or
  customer-offers code; staff has no vendor, admin or offers code. (Debug builds are not tree-shaken, so only release counts.)
  The customer WEB build still contains the `/jyothi9` admin route (kept until the owner says to remove it).
- `functions/role-matrix.test.js`: every role (anonymous, customer, vendor, other vendor, staff, other staff, Quick Add staff, Quick
  Add vendor, admin, a forged admin claim with no OTP session) against every private collection, reads and writes. Passes.
- Not done / owner's call later: Firebase App Check (needs Play Integrity setup in the console; enforcing it could lock out the
  live apps, so it is off until the new apps are released); removing `/jyothi9` from the customer web app.
