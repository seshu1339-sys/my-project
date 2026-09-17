# Firebase production verification — 17 September 2026

Subsequent authentication changes supersede the SMS status below: Email/Password is now enabled and Phone is disabled. The new client and backend migration await deployment approval. See [the authentication deployment scope](authentication-deployment.md) for the current state and passwordless support.

Project: `e-commerce-app-a3897`. This follow-up inspected the live backend using the existing Firebase CLI login. No UI/layout source, production data, authentication users, IAM bindings, billing settings, or deployments were changed. Previously completed Flutter/Chrome tests were not repeated.

## Verified live

| Area | Result |
| --- | --- |
| Billing | Enabled |
| Phone authentication | Enabled; SMS region allowlist includes India (`IN`) |
| Authorized web domains | `localhost`, `e-commerce-app-a3897.firebaseapp.com`, `e-commerce-app-a3897.web.app` |
| Storage | Existing default bucket in `ASIA-SOUTH1` |
| Firestore and Storage rules | Deployed rule source matches local files |
| Commerce functions | `pinLogin`, `setPin`, `placeOrder`: ACTIVE, Node.js 22, `us-central1` |
| Function transport/auth guards | Invalid PIN-login payload returns INVALID_ARGUMENT; unauthenticated PIN-setting and checkout return UNAUTHENTICATED, as expected |
| Runtime token signing | Existing service account has self-token-signing permission |
| Notifications | `notifyPriceDrop` and `notifyNewOffers` ACTIVE in `asia-south1`; offer schedule ENABLED every 15 minutes; FCM API ENABLED |
| Hosting | HTTPS bundle responds HTTP 200; hosted bundle differs from the current locally verified build |
| Composite indexes | API returned no composite indexes; no index error was observed in these checks |

The hosted build was not replaced: this request is limited to backend setup and verification and preserves the current UI. A binary mismatch is not proof of a runtime error, but means local Chrome results cannot be claimed as verification of the exact hosted bundle.

## Blockers requiring the owner's input or interaction

1. **SMS and administrator account:** Firebase Auth currently contains zero users (complete account listing, no next page). Therefore no registered SMS user or administrator exists. Open the live-configured app's Account screen, choose SMS registration/recovery, enter the owner's international phone number, complete reCAPTCHA and OTP, and set a PIN. Do not send the PIN/password in chat. Identify the intended owner phone or UID before its existing account receives the admin claim. Refresh the sign-in session after the claim is granted.
2. **Real order:** The only returned product is `rice` (`xNGqNwWQbeVtYRHu3sLJ`); the inspected record has no price, stock or active field. The server's checkout validator requires an active product with numeric stock and price. Supply the intended product data, quantity, delivery pincode and full address. A genuine production order reduces stock and remains a production business record; it was not fabricated for this check. Checkout currently submits an order request with `pending_arrangement` payment status, not an online payment charge.
3. **Admin writes/uploads:** Require the registered owner and admin claim above. Then save a clearly identified unpublished verification record through Business studio, reload to verify persistence, and test an owner-selected image upload. No privileged server credential was substituted for the client admin flow.
4. **Web push:** `FIREBASE_VAPID_KEY` is absent from the local web build configuration. Supply the public Web Push certificate key from Firebase Console → Project settings → Cloud Messaging → Web configuration. It must be included in a build before deployment; a signed-in browser must explicitly allow notifications. Real push receipt has not been verified. iOS still needs APNs/Xcode/device setup.
5. **Voice/image search and online payments:** Recognition adapters/providers and payment processing are not configured. See [search-provider-setup.md](search-provider-setup.md). No provider account, payment gateway, or paid API was selected or enabled in this follow-up.

## Errors and limitations

No unexpected error was returned by the three negative callable checks. Their HTTP 400/401 responses are expected validation/authentication results, not failed deployments. The production gaps are the empty Auth user list, incomplete product data, missing public VAPID configuration, unconnected recognition providers, and the hosted/local bundle difference.

The initial temporary audit parser could not read the UTF-8 BOM in the web configuration JSON. The harness was corrected to strip the BOM; the application configuration was not altered, and the subsequent readiness check succeeded.

Successful SMS delivery, PIN setup/login with a real account, authenticated order creation, admin client writes/uploads, and actual push delivery remain **unverified**, not passed. Their next steps depend on the owner inputs above.

Raw non-secret inspection summaries: `build/production-check/audit.json` and `build/production-check/readiness.json`. Temporary scripts are under `build/production-check/` and are not app dependencies.
