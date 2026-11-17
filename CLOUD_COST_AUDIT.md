# LOCAMARKET: Google Cloud ఖర్చు audit (STEP 0), 12 Nov 2026

ఈ audit లో చదవడం మాత్రమే చేశాను. Cloud లో గానీ code లో గానీ ఏదీ మార్చలేదు, ఏదీ delete చేయలేదు.
Project: `e-commerce-app-a3897`. Billing account కి ఈ ఒక్క project మాత్రమే link అయి ఉంది. Budget alert ఒక్కటి కూడా లేదు.
Usage సంఖ్యలు Cloud Monitoring నుండి తీసుకున్నాను (గత 30 నుండి 42 రోజులు).

## 1. ప్రతి service: ఇప్పుడు ఉన్నది, free limit, ఖర్చు కారణం

| Service | ఇప్పుడు ఉన్నది | Free limit | ఖర్చు ఎందుకు వస్తోంది |
|---|---|---|---|
| **Cloud Scheduler** (₹37) | **13 jobs**, అన్నీ ON | billing account కి 3 jobs | 3 కంటే ఎక్కువ ఉన్న ప్రతి job కి నెలకు $0.10. 10 అదనపు jobs = నెలకు సుమారు ₹84. పూర్తి నెల కాకపోవడంతో ₹37 వచ్చింది. |
| **Secret Manager** (₹44) | 14 secrets, **20 active versions** | 6 active versions, నెలకు 10,000 accesses | 6 దాటిన ప్రతి version కి నెలకు $0.06. 14 అదనపు versions = నెలకు సుమారు ₹70. Accesses 30 రోజుల్లో 1,654 మాత్రమే (free లోనే). |
| **Artifact Registry** (₹3.84) | `gcf-artifacts` 2 repos, 945 MB + 1,165 MB = **2.1 GB**, 118 images, cleanup policy లేదు | 0.5 GB | 1.6 GB అదనం = నెలకు సుమారు ₹13. |
| **Cloud Storage** (₹0.36) | 5 buckets (క్రింద వివరాలు) | 5 GB, కానీ **US regions లో మాత్రమే** | asia-south1 లో ఉన్న buckets కి free tier లేదు: మొత్తం సుమారు 111 MB. |
| **Cloud Run functions** (₹118) | **182 functions** (151 us-central1, 31 asia-south1), అన్నీ min instances = 0 | 180,000 vCPU-sec, 360,000 GiB-sec, 2 million requests | Monitoring ప్రకారం usage free లోపలే ఉంది (క్రింద చూడండి). ₹118 ఏ SKU కిందో **Billing Reports లో మాత్రమే కనిపిస్తుంది**. నా login కి billing costs చదివే అనుమతి లేదు, billing export కూడా లేదు. |
| Cloud Build | 30 రోజుల్లో సుమారు 13 build-minutes | నెలకు 2,500 నిమిషాలు | ఖర్చు లేదు. |
| Firestore (asia-south1) | Reads: రోజుకు సగటు 6,291, max 15,496. Writes: సగటు 743, max 3,449. Deletes: max 26 | రోజుకు 50,000 reads, 20,000 writes, 20,000 deletes | ఖర్చు లేదు. Max day లో reads 31%, writes 17%. |
| Google Maps | `maps-android-backend` (Maps SDK for Android) మాత్రమే ON | Android SDK map display free | ఖర్చు లేదు. Geocoding, Places, Directions APIs **ఆన్‌లో లేవు**. Area పేర్లు OpenStreetMap నుండి వస్తాయి (free). |
| Cloud Vision | 30 రోజుల్లో 2 calls (admin photo check) | నెలకు 1,000 units | ఖర్చు లేదు. |
| App Engine | **App Engine app లేదు.** API మాత్రం ON | – | ఖర్చు లేదు. API ఆపేయవచ్చు. |

### Cloud Run: 30 రోజుల్లో నిజమైన usage
- Billable instance time: **18,460 sec**. 42 రోజుల్లో CPU allocation 61,009 vCPU-sec. Free limit నెలకు 180,000.
- Requests: **15,665** (free limit 2 million). Internet కి పంపిన data: 0.4 MB.
- ఎక్కువ requests వస్తున్నవి: `trackEvent` 6,176, `notifyNewOffers` 2,881, `expireQuickItems` 2,079, `trackUsage` 1,146, `expireVendorPrices` 834.
- ఎక్కువ instance time వాడుతున్నవి: `trackEvent` 6,373 s, `expireVendorPrices` 2,677 s, `trackUsage` 1,866 s.
- 182 services అన్నీ: min instances 0, CPU throttling ON (requests లేనప్పుడు CPU కి bill లేదు), startup CPU boost ON.
  - Memory: 256 MiB 179 services, 512 MiB 3 services.
  - Max instances: 10 → 129 services, 5 → 23, 3 → 14, 2 → 3, 1 → 13.
- Code లో లేని పాత functions ఏవీ deploy అయి లేవు. 182 deployed functions అన్నీ code లో ఉన్నాయి.
- **తీర్మానం:** monitoring ప్రకారం Cloud Run usage free limit లోనే ఉంది. ₹118 ఏ SKU కిందో నిర్ధారించడానికి
  Console → Billing → Reports → *Group by: SKU* → Service = Cloud Run screenshot కావాలి.
  - సాధ్యమైన కారణం 1: asia-south1 (Tier 2 region) లో free tier లెక్క వేరుగా ఉండడం.
  - సాధ్యమైన కారణం 2: ఖర్చు గత నెలలో వచ్చి ఉండడం.

### Cloud Scheduler: 13 jobs
| Job | ఎప్పుడు | ఏమి చేస్తుంది |
|---|---|---|
| expireQuickItems | ప్రతి 15 ని. | Quick items గడువు ముగిసినవి ఆపుతుంది |
| expireVendorPrices | ప్రతి 30 ని. | Vendor prices గడువు |
| clearTodaysOffers | ప్రతి 15 ని. | Today's Offers గడువు |
| expirePremiumStatus | ప్రతి 15 ని. | Premium plan గడువు |
| notifyNewOffers | ప్రతి 15 ని. | కొత్త offers push |
| aiAgentHealthCheck | ప్రతి 6 గం. | AI agent health email |
| aiAgentDailyBackup | రోజుకు ఒకసారి | AI agent backup |
| dailyStorageMaintenance | రోజుకు ఒకసారి | Storage శుభ్రం |
| sweepInactiveAccounts | రోజు 03:30 IST | పాత accounts |
| staffAreaNightly | 00:20 | Staff areas రాత్రి లెక్క |
| staffAreaLastChance | 17:00 | Staff target గుర్తు |
| sendAdSummaries | 08:30 IST | Vendor ad summary |
| weeklyStorageUsage | సోమవారం 03:00 | Storage usage |

### Secret Manager: 14 secrets, 20 active versions
| Secret | Active versions | Functions వాడే version | గమనిక |
|---|---|---|---|
| ADMIN_MAIL_PASSWORD | 5 (v1–v5) | v5 | v1–v4 పాతవి |
| ADMIN_MAIL_USER | 2 | v2 | email address, అసలు secret కాదు → env variable కావచ్చు |
| ADMINMAILPASSWORD | 2 | ఏ code వాడదు | **పూర్తిగా వాడనిది** (పేరులో తప్పు ఉన్న పాత copy) |
| ADMIN_OTP_PEPPER | 1 | v1 | అవసరం |
| AI_AGENT_ANTHROPIC_API_KEY | 1 | v1 | ANTHROPIC_API_KEY కి duplicate అయి ఉండవచ్చు |
| ANTHROPIC_API_KEY | 1 | v1 | ai-core లో వాడుతారు |
| AI_AGENT_OPENAI_API_KEY | 1 | v1 | AI agent |
| AI_AGENT_GITHUB_APP_PRIVATE_KEY | 1 | v1 | AI agent |
| AI_AGENT_PIN_PEPPER | 1 | v1 | AI agent |
| GITHUB_APP_PRIVATE_KEY | 0 | – | ఖాళీ (ఖర్చు లేదు), delete చేయవచ్చు |
| RAZORPAY_KEY_ID | 1 | v1 | public key id, అసలు secret కాదు → env variable కావచ్చు |
| RAZORPAY_KEY_SECRET | 1 | v1 | అవసరం |
| RAZORPAY_WEBHOOK_SECRET | 2 | v2 | v1 పాతది |
| REVIEW_LOGIN_CODE | 1 | v1 | అవసరం |

వాడని, పాత versions 8 ఉన్నాయి (ADMINMAILPASSWORD 2, ADMIN_MAIL_PASSWORD v1–v4, ADMIN_MAIL_USER v1, RAZORPAY_WEBHOOK v1). ఇవి తీసేసినా **12** మిగులుతాయి.
6 కి తగ్గించాలంటే:
- ADMIN_MAIL_USER, RAZORPAY_KEY_ID ని env variables గా మార్చాలి.
- రెండు Anthropic keys ని ఒకటిగా కలపాలి.
- AI agent secrets (OpenAI, GitHub, PIN pepper) పై మీ నిర్ణయం కావాలి.

### Cloud Storage buckets
| Bucket | Region | Size | Free region లో ఉందా? |
|---|---|---|---|
| e-commerce-app-a3897.firebasestorage.app (photos) | ASIA-SOUTH1 | 23 MB | కాదు |
| gcf-v2-sources-…-asia-south1 (function source zips) | ASIA-SOUTH1 | 85 MB | కాదు |
| gcf-v2-sources-…-us-central1 | US-CENTRAL1 | 415 MB | అవును |
| gcf-v2-uploads-….asia-south1 | ASIA-SOUTH1 | 2.7 MB | కాదు |
| gcf-v2-uploads-….us-central1 | US-CENTRAL1 | 0 | అవును |

**Photos bucket region:** asia-south1 (Mumbai) లో ఉంది. Always Free 5 GB US regions (us-central1, us-east1, us-west1) లో మాత్రమే వర్తిస్తుంది.
- Default Firebase bucket region ని మార్చడం సాధ్యం కాదు. మార్చాలంటే కొత్త bucket సృష్టించాలి, photos అన్నీ copy చేయాలి, Firestore లో ఉన్న photo URLs అన్నీ మార్చాలి, apps/website config మార్చాలి.
- 23 MB కి ఖర్చు నెలకు సుమారు ₹0.05. **Move చేయవద్దని సిఫారసు.**
- asia-south1 లోని function source zips (85 MB) కి lifecycle rule పెట్టి పాత zips తీసేయవచ్చు.

### API keys
- Staff Maps Android key: 3 package names + SHA-1 తో, Maps SDK మాత్రమే. ✓ సరిగ్గా restrict అయి ఉంది.
- Android key (Firebase auto): API list ఉంది, కానీ **app restriction లేదు**.
- Browser key (Firebase auto): **website restriction లేదు**.
- iOS key: iOS app లేకపోయినా ఉంది.

### Enabled APIs: వాడనివి (ఆపివేయడానికి అనుకూలం)
`appengine`, `containerregistry` (పాతది), `deploymentmanager`, `sql-component`, `source`, `testing`, `cloudaicompanion`, `dataform`, `dataplex`, `analyticshub`, `bigqueryconnection`, `bigquerydatapolicy`, `bigquerydatatransfer`, `bigquerymigration`, `bigqueryreservation`.
- ON లో ఉన్నంత మాత్రాన వీటికి ఖర్చు రాదు. మీ నియమం ప్రకారం ఆపవచ్చు.
- ఉంచవలసినవి: `vision` (photo check), `runtimeconfig`, `bigquery`, `bigquerystorage` (Firebase/analytics వాడవచ్చు).

## 2. ముఖ్యమైన గమనికలు (plan కి ముందు మీరు తెలుసుకోవాలి)
1. **Artifact Registry "ప్రతి service కి 2 images" + "0.5 GB లోపు" రెండూ ఒకేసారి సాధ్యం కాదు.**
   - 86 image packages ఉన్నాయి, ఒక్కొక్కటి సుమారు 15–20 MB. ఒక్కో దానికి 1 image ఉంచినా 1.3 GB పైనే.
   - Firebase సూచించిన విధానం: `firebase functions:artifacts:setpolicy --days 1`, అంటే 1 రోజు దాటిన images తీసేయడం. Deploy అయిన functions పనిచేస్తూనే ఉంటాయి (Cloud Run తన సొంత copy ఉంచుకుంటుంది).
   - Rollback కావాలంటే code git లో ఉంది కాబట్టి మళ్ళీ deploy చేయవచ్చు.
2. **Secrets "latest" విషయం:**
   - Firebase deploy చేసే సమయంలోనే ఒక version number ని fix చేస్తుంది. "latest" ని runtime లో చదవాలంటే code మార్చాలి, అప్పుడు ప్రతి cold start కి access లెక్కలోకి వస్తుంది.
   - సులభమైన సురక్షిత మార్గం: secret update చేసిన ప్రతిసారి `firebase deploy` చేయాలి, ఆ వెంటనే పాత version ని destroy చేయాలి. దీనికి ఒక script ఇస్తాను.
3. **₹1 kill switch (billing disable):**
   - Billing ఆపితే **అన్ని Cloud Functions ఆగిపోతాయి**: login codes, payments, notifications, expiry అన్నీ.
   - ఎక్కువ రోజులు billing off గా ఉంటే Google కొన్ని resources ని delete చేయవచ్చు.
   - Billing data కొన్ని గంటలు ఆలస్యంగా వస్తుంది. కాబట్టి ఇది "చివరి రక్షణ" మాత్రమే.
   - **ఇప్పుడు నెలకు సుమారు ₹200 ఖర్చు వస్తోంది. ముందే ఆన్ చేస్తే వెంటనే అంతా ఆగిపోతుంది.** STEP 1–5 పూర్తి చేసి, ఒక billing cycle ₹0 అని చూసిన తర్వాతే ఆన్ చేయాలి.
   - దీనికి function కి billing account admin అనుమతి ఇవ్వాలి. ఇప్పుడు నా login కి billing budgets చదవడానికి కూడా అనుమతి లేదు.
4. **asia-south1 storage లో పైసల ఖర్చు** పూర్తిగా ₹0 కాకపోవచ్చు (నెలకు ₹0.05–0.2), bucket ని US కి మార్చకపోతే.
   - ₹1 kill switch దీనితో trigger కాకుండా threshold జాగ్రత్తగా పెట్టాలి.
5. **Messages:**
   - Admin app కి push (FCM): free.
   - Email: ఇప్పుడు ఉన్న Gmail SMTP తో free.
   - WhatsApp Business API లో ప్రతి message కి డబ్బు అవుతుంది, అందుకే **సిఫారసు చేయను**.
6. **Usage guard:**
   - Cloud Monitoring నుండి usage చదవడం free (నెలకు 1 million API calls వరకు).
   - Guard ని ఒకే scheduler job లో కలిపితే అదనపు job ఖర్చు ఉండదు.

## 3. Step 1 గురించి ప్రశ్న (expiry)
ఇప్పటికే గడువు ఉన్నవి: quick items, vendor prices, Today's Offers, premium status.
"Every item posted by anyone" లో **shop catalogue products** (vendor shop లో శాశ్వతంగా ఉండే items) కూడా గడువుతో ఆగిపోవాలా?
లేక posts (quick items, offers, ads, prices) మాత్రమేనా? ఇది మీ నిర్ణయం.
