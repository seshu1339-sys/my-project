# Pending tasks: Analytics పని (రాత్రి 25→26 అక్టోబర్ 2026)

అంతా branch `analytics` లో ఉంది (main నుండి వేరుగా). **ఏదీ deploy చేయలేదు, GitHub కి push చేయలేదు, Play Store కి upload చేయలేదు, ఏదీ delete చేయలేదు, Google Cloud లో ఏ setting మార్చలేదు.**
ప్రతి part తర్వాత `flutter analyze` (0 errors, 0 warnings) మరియు అన్ని tests run చేశాను: app tests 713 pass, backend tests 133 pass.

---

## 1. ముందే ఉన్నవి (మీ Analytics prompt లోని 8 parts లో)

| Part | ముందే ఉన్నది | లేనిది |
|---|---|---|
| 1. Setup check | Firebase 4 apps లో (database, login, photos, functions, hosting). Push notifications customer app లో (Android + website). Cloud Vision photo check | Crashlytics, Performance, Google Analytics SDK ఏ app లోనూ లేవు. Setup check page లేదు |
| 2. Analytics options | Ads views/taps లెక్క (adStats). Website visits లెక్క | Google Analytics dashboard (live users, retention, paths...) apps కి connect అవ్వలేదు |
| 3. ప్రతి button | లేదు | ఏ button ఎంత వాడారో లెక్క లేదు |
| 4. Admin reports | ప్రతి ad views/taps. Staff report (staff spec లో చేసినది) | Shop calls/WhatsApp/directions, searches, per-person report, Excel, apps లో "Your numbers" |
| 5. Inactive accounts | లేదు | — |
| 6. Push notifications | Automatic: price drops, new offers, offers in your town, order updates | Admin నుండి పంపడం, opened/not-opened report, ON/OFF switches |
| 7. Cost safeguards | Functions కి rate limits, maxInstances | Analytics కి limits |
| 8. Privacy policy | Page + PDF + delete-account page ఉన్నాయి | Analytics గురించి lines లేవు |

## 2. కొత్తగా చేసినవి (commits, branch `analytics`)

1. **Part 1, usage tracking** (`c698590`): customer, vendor, staff, admin 4 apps నుండి events: shop_call, shop_whatsapp, shop_directions, worker_call, worker_whatsapp, map_view, price_list_view, service_open, search, search_no_result, location_change, offer_click, transport_click, screens, buttons. Server లో: vendor_register, item_added, price_changed, ad_interest, staff_added. లెక్కలు మాత్రమే దాచుతాం (ప్రతి click log కాదు).
2. **Part 2, Admin > Insights > Analytics > Reports + People** (`5d94f89`): 7/30/90 రోజుల reports, shops వారీగా calls/WhatsApp/directions, ఎక్కువ వెతికినవి, వెతికి దొరకనివి, towns, offers, ads, Transport demand, vendor registrations, staff పని, **ప్రతి screen/button ఎన్నిసార్లు వాడారు (ఎప్పుడూ వాడనివి కూడా)**. People: ప్రతి వ్యక్తి (customer కూడా) ఏం వాడారు. ప్రతి table కి Excel download.
3. **Part 3, "Your numbers"** (`43c4d20`): vendor app (calls, WhatsApp, directions, items, prices), provider (calls, WhatsApp), staff app (additions + వాళ్ళు add చేసిన vendors కి calls) లో 7 మరియు 30 రోజుల లెక్కలు.
4. **Part 4, Push notifications centre** (`cd55f9a`): అందరికీ / ఒక town కి / ఒక వ్యక్తికి (email తో) పంపడం, confirmation తో. ప్రతి notification కి ఎంతమందికి వెళ్ళింది, ఎంతమంది open చేశారు, open చేయని వాళ్ళ list (email తో). Notifications off చేసుకున్న వాళ్ళ సంఖ్య (town వారీగా). ప్రతి automatic notification కి ON/OFF switch + 30 రోజుల sent/opened.
5. **Part 5, Inactive accounts** (`0e8a4b4`): 7/30/90 రోజులు వాడని accounts list, Disable/Enable, Delete (customers మాత్రమే, DELETE అని type చేస్తేనే; orders ఉంటాయి), Excel. **Automatic disable (30 రోజులు) మరియు automatic delete (90 రోజులు) switches OFF లో ఉన్నాయి**, మీరు ON చేస్తేనే పని చేస్తాయి. Vendor, provider, staff accounts automatic గా delete కావు.
6. **Setup check + errors + speed + Google Analytics (website)** (`8e8590c`): Admin > Analytics > Setup check: ఏది connect అయిందో, ఏది మీ step కోసం ఆగిందో. ప్రతి app ఎన్నిసార్లు open అయింది, ఎంత వేగంగా (1 సెకను లోపు...), errors, crashes (message తో). Crashlytics కి బదులు ఇది website తో సహా అన్ని apps లో పని చేస్తుంది. Website (customer, vendor, staff) Google Analytics కి కూడా పంపుతుంది: age/gender వద్దు (Google signals off), ad personalisation off, account id పంపము. Admin panel GA కి పంపదు.
7. **Privacy policy** (`208991a`): పై అన్నింటి గురించి lines, PDF మళ్ళీ తయారు చేశాను.
8. **Fix + cost guard** (చివరి commit): "Your numbers" card 60 రోజుల తర్వాత పాత రోజులు చూపించే bug fix (కొత్త index కావాలి, క్రింద చూడండి). Apps 10 సెకన్లకు ఒకసారి కాకుండా 30 సెకన్లకు ఒకసారి పంపుతాయి (writes 3 రెట్లు తక్కువ), app వదిలేసినప్పుడు వెంటనే పంపుతాయి.

**Cost safeguards (Part 7), మొత్తం:** fixed event list మాత్రమే; ఒక device కి రోజుకు 400 events; ఒక్కో పంపకం 50 events, ఒకే write గా కలిపి; 30 సెకన్లకు ఒకసారి; bots ని లెక్కించదు; errors run కి 5 మాత్రమే; per-person records 400 రోజుల తర్వాత తీసేయడానికి TTL (మీ step 5); push ఒక్కసారికి 5000 మంది వరకు; inactive sweep రాత్రికి 200 మాత్రమే; Cloud Vision నెలకు 1000 (free); reports tab open చేసినప్పుడే చదువుతాయి. కొత్త scheduled job (inactive sweep) వల్ల Cloud Scheduler నెలకు సుమారు $0.10.

**ఒక local file మార్చాను:** `firebase-config-web.json` లో `FIREBASE_MEASUREMENT_ID` (Google Analytics web id, మీ `firebase-config-web-sdk.json` లో ముందే ఉన్నది) add చేశాను. ఈ file git లో లేదు (.gitignore). పాత copy: `C:\Users\Lappy\AppData\Local\Temp\claude\c--Users-Lappy-ecommerce-app\a8e6bc34-7c20-4611-9da7-4573398c2e01\scratchpad\firebase-config-web.backup.json`.

## 3. మీ అనుమతి కోసం ఆగినవి

1. **`analytics` branch ని `main` లో merge చేయడం.**
2. **Functions deploy** (మీరు run చేస్తారు): కొత్తవి trackUsage, accountLabels, sendPushNotification, trackPushOpen, pushAudience, pushNotOpened, inactiveAccounts, setAccountDisabled, deleteInactiveAccount, sweepInactiveAccounts (scheduled). మారినవి registerVendor, submitVendorChange, setAdInterest, staff functions, notifications.
3. **Firestore rules + indexes deploy** (కొత్త index: usageOwnerDaily ownerId + day).
4. **Hosting 4 sites + Hostinger (locamarket.in) deploy.**
5. **Firestore TTL policies** (Google Cloud setting): `usagePersonDaily` → `expiresAt`, `_usageDevices` → `expiresAt`.
6. **Android apps లో Google Analytics:** ఇది పెద్ద మార్పు కాబట్టి చేయలేదు. Firebase నుండి 3 apps కి config file (google-services.json) తీసుకుని, Gradle plugin add చేయాలి. అలా చేస్తే Android app local emulator test mode పని చేయదు, Play Data safety form కూడా మార్చాలి. Android లో ఇప్పటికే మన సొంత analytics (screens, buttons, errors, speed, ప్రతి వ్యక్తి) ఉంది, installs/uninstalls/phones Play Console లో ఉంటాయి. **నా సూచన: ఇప్పుడు వద్దు.** కావాలంటే చెప్పండి, చేస్తాను.
7. **Play Store:** 3 apps కొత్త AAB build + upload, మరియు Data safety form update: "App activity: App interactions", "App info and performance: Crash logs, Diagnostics", "Device or other IDs" (random device id). Collected: అవును, shared: లేదు, purpose: Analytics.
8. **GitHub push** (`main`; GitHub లో ఉన్నది చాలా పాతది, `336e680`).
9. ముందు నుండి pending: productImageLibrary photos నింపడం, `node scripts/migrate-services-to-collection.cjs --delete-originals` (delete), AI_HANDOFF.md update, CUSTEMER spelling (మీరే మారుస్తారు), Nominatim User-Agent కి support email.

## 4. Errors

- ఏ part కూడా error తో ఆగలేదు.
- కనుక్కుని fix చేసినది: Part 3 "Your numbers" 60 రోజుల తర్వాత 0 చూపించే bug. Index deploy అయ్యే వరకు పాత విధంగానే చూపిస్తుంది (మొదటి 60 రోజులకు సరైనదే).
- Crashlytics, Performance add చేయలేదు: Android build config మార్చాలి, website లో పని చేయవు. వాటి బదులు అన్ని apps లో (website తో) errors, speed లెక్క Setup check లో ఉంది.
- `flutter analyze`: 0 errors, 0 warnings. పాత files లో 12 "info" సూచనలు ముందు నుండే ఉన్నాయి, వాటిని నేను ముట్టుకోలేదు.

## 5. ఉదయం మీరు చేయాల్సినవి (step by step)

1. ఈ file చదవండి.
2. Deploy ముందు చూడాలంటే "screenshots చూపించు" అని చెప్పండి: Analytics tabs (Reports, People, Push notifications, Inactive accounts, Setup check) local గా చూపిస్తాను.
3. "deploy చేయి" అని చెప్పండి. నేను: `analytics` ని `main` లో merge చేసి, clean build (`git archive HEAD` నుండి) చేసి, Firestore rules + indexes, 4 hosting sites, Hostinger deploy చేస్తాను.
4. మీరు functions deploy చేయండి:
   `cd C:\Users\Lappy\ecommerce_app; $env:FUNCTIONS_DISCOVERY_TIMEOUT="120"; firebase deploy --only functions`
5. TTL policies on చేయండి (Firebase console > Firestore > TTL, లేదా ఈ 2 commands):
   `gcloud firestore fields ttls update expiresAt --collection-group=usagePersonDaily --enable-ttl --project=e-commerce-app-a3897`
   `gcloud firestore fields ttls update expiresAt --collection-group=_usageDevices --enable-ttl --project=e-commerce-app-a3897`
6. Admin panel లో Insights > Analytics open చేసి 5 tabs చూడండి. Setup check లో ✓ లు చూడండి (కొత్త version వాడిన తర్వాత starts/errors వస్తాయి).
7. Inactive accounts automatic switches OFF లో ఉన్నాయి. కావాలంటే మాత్రమే ON చేయండి.
8. Google Analytics: Firebase console > Analytics > Dashboard లో website data రావడం మొదలవుతుంది (deploy తర్వాత కొన్ని గంటల్లో).
9. Android: 3 apps build చేసి Play Console కి upload, Data safety form update (step 3.7).
10. "GitHub push చేయి" అని చెప్పినప్పుడు push చేస్తాను.
11. Android Google Analytics కావాలో వద్దో చెప్పండి (step 3.6).
