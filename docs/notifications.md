# Customer views and push alerts

Startup calls `WidgetsFlutterBinding.ensureInitialized()` and awaits `Firebase.initializeApp(options: ...)` before obtaining `FirebaseFirestore.instance`. Build defines select the existing live Firebase project; builds without them remain demo builds.

Signed-in product page visits update `products/{productId}/viewers/{uid}` with a server timestamp and the current pincode. Rebuilds do not create extra views. Guest visits are not recorded. Rules restrict these records to the customer and trusted backend. Views are used for price alerts for 90 days; that eligibility window does not delete historical records.

Customers explicitly enable price-drop and offer alerts in Account. Permission denial or missing web configuration produces an actionable error. `notificationSubscribers/{uid}` stores the account opt-in; private `users/{uid}/pushTokens/{token}` documents register devices. Tokens refresh when the signed-in app restores an enabled registration. Disabling alerts or logging out opts the whole account out and deletes the current device's FCM token. Other devices can enable the account again. Queued notifications may already be in transit.

`notifyPriceDrop` handles product updates in Mumbai. It compares old/new prices at each recent viewer's pincode, with base-price fallback, and ignores unavailable schedules, price increases and unrelated edits. `notifyNewOffers` checks active promotions every 15 minutes, including scheduled starts, and sends each offer/start-date combination once per opted-in customer. Newly opted-in customers receive currently active offers. Changing the offer's start date creates a new campaign; text-only edits do not resend it.

Notifications contain display text, item/offer IDs, and no phone number or authentication credentials. Foreground messages appear as an in-app snackbar; mobile notification taps open the item, and web notifications open the storefront. The OS/FCM displays notification payloads in the background. Invalid device tokens are removed by the backend.

Mobile startup registers the top-level `firebaseMessagingBackgroundHandler` before `runApp()`. Its `@pragma('vm:entry-point')` preserves it in release builds, and it initializes Firebase in the background isolate with the same build configuration as the foreground app. It does not access UI or create duplicate notifications. Web background callbacks run in the JavaScript service worker instead. Data-only application work can be added to these handlers when needed; push receipt is still subject to platform delivery restrictions.

Delivery claims under `_notificationDeliveries` prevent duplicate event dispatch. Claims are written before sending: a crash or transient FCM error after a claim can lose an alert. This is best-effort delivery, not a guaranteed queue. Logs record failure counts without tokens. Jobs page through viewers/subscribers and batch FCM calls; large catalogs/customer bases should move to a dedicated queued campaign system. Review retention for views, tokens and delivery claims as the store grows.

## Platform setup

- Android: the Messaging plugin and notification permission are included. Users must grant permission, and the device needs compatible Google Play services.
- Web: add the **public** Firebase Web Push certificate key as `FIREBASE_VAPID_KEY` in the ignored `firebase-config-web.json`, then rebuild/deploy. Do not add a private VAPID key. `web/firebase-messaging-sw.js` loads public config from Firebase Hosting's `/__/firebase/init.js`; local push testing requires Firebase Hosting emulator/preview rather than a generic static server. HTTPS is required outside localhost.
- iOS: configure APNs credentials in Firebase and enable Push Notifications and Background Modes / Remote notifications in Xcode, then build/sign on macOS. No Apple credentials are included here.

References: [Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [receiving messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Verification

`node scripts/firebase-setup.cjs inspect-notifications` checks both deployed function states, the offer schedule and FCM API status using the signed-in Firebase CLI. Both functions and the schedule are deployed; web VAPID configuration and real-device acceptance are still pending.

Tests cover pincode price drops, offer schedules, ownership of views/tokens/subscriptions, forbidden delivery-claim writes, and one recorded view per product visit. For device acceptance, sign in, enable alerts, open a product, background the app, and lower that product's applicable price in Admin. Confirm one push, tap through to the item, then disable alerts and verify subsequent changes send none. Test a new scheduled promotion after its start time. This acceptance check requires an actual opted-in browser/device; automated tests do not establish real push delivery.
