# Implementation status — 14 September 2026

Customer storefront and admin studio implemented; see README for capabilities and integration boundaries.

## Verified

- Flutter dependencies installed.
- Flutter analysis: no issues.
- Nine Flutter tests: pass, including mobile/desktop layout, search, cart and admin form editing.
- Four backend domain tests: pass.
- Firestore emulator security test: pass (role escalation, private data, forged orders, reviews and order ownership).
- Backend callable module loads successfully.
- npm dependency audit: zero vulnerabilities after updates and an npm-10-compatible UUID override. Clean npm 10 install and backend tests pass.
- Web release and Android debug APK build successfully. Web build with Firebase configuration also succeeds.
- iOS is scaffolded and registered, but cannot be built on this Windows machine.
- Browser automation is unavailable; no manual browser/device end-to-end claim is made.

## Firebase changes completed

Project: `e-commerce-app-a3897`.

- Registered web, Android and iOS applications matching existing package/bundle identifiers.
- Downloaded platform client configuration into Git-ignored files and generated build-define files.
- Registered local Android debug SHA-1 and SHA-256 fingerprints.
- Deployed tested Firestore rules and indexes.
- Blaze billing is enabled. Created the default Storage bucket in `asia-south1` and deployed Storage security rules.
- Rechecked project setup: Phone authentication is enabled and web/localhost domains are authorized. Enabled India (`IN`) in the previously empty SMS region allowlist and verified the result.
- Added a credential-safe Firebase inspection/setup helper using the signed-in CLI, including owner-account lookup and claim assignment after registration.
- Published the Firebase-connected website at https://e-commerce-app-a3897.web.app and verified that the hosted bundle matches the local release exactly.
- Built the Firebase-connected Android debug APK.
- All three Node 22 Functions (`pinLogin`, `setPin`, `placeOrder`) are deployed and active after repairing the npm lockfile.
- Enabled the signing API and granted the runtime service account token-signing permission on itself; verified the binding.
- Redeployed all three Functions and applied the owner's approved public invocation permissions to their Cloud Run services, preserving existing IAM bindings.
- Live smoke checks pass: exact hosted release, invalid PIN-login input rejection, and unauthenticated PIN-setting/order rejection.

## External actions still needed

1. Deployment and public invocation are complete and verified. No further invocation approval is pending.
2. The owner number has been provided privately, but is not yet registered in Firebase Auth. Verify it by SMS, choose a PIN, then grant its Auth UID the admin claim. No owner phone number is stored in this repository.
3. Real SMS verification, signed-in checkout and admin uploads still need end-to-end verification. Live negative Function checks pass.
4. GitHub is connected at https://github.com/seshu1339-sys/my-project on branch `main`; authentication succeeded and the implementation has been pushed. A separate project-local repository keeps personal home-folder files outside version control.
5. Complete iOS signing/APNs and release signing before store publication. Review APK uses debug signing.

The hosted website and current Android APK use live Firebase configuration. Running Flutter without build defines still opens the labelled demo. Online payment processing and voice/image recognition remain provider integrations, as documented in README. Artifact Registry image cleanup is currently opted out; choose a retention policy before accumulating repeated production releases.
