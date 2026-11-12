# LOCAMARKET ఆడిట్ రిపోర్ట్ — 3 నవంబర్ 2026

స్కాన్ చేసిన బ్రాంచ్: `ai-care` (కమిట్ `36c73ef` + నేటి చిన్న మార్పులు). బ్యాకప్ బ్రాంచ్: **`audit-backup`** (ఆడిట్ మొదలుపెట్టినప్పటి HEAD).

> మీరు ఫోల్డర్ పాత్‌లు ఇవ్వలేదు, కానీ నాలుగు యాప్‌లు + వెబ్‌సైట్ అన్నీ **ఒకే repo** (`ecommerce_app`) లో ఉన్నాయి: యూజర్ `lib/main.dart`, వెండర్ `lib/main_vendor.dart`, స్టాఫ్ `lib/main_field.dart`, అడ్మిన్ `lib/main_admin.dart`, వెబ్‌సైట్ `web/`. అందుకే రూట్ నుంచే స్కాన్ చేశాను.
>
> **ఏమీ డిలీట్ చేయలేదు. DB, పేమెంట్ లాజిక్, auth, ప్యాకేజీ వెర్షన్లు, Firebase/సర్వర్ config ముట్టుకోలేదు.** కమిట్ కూడా చేయలేదు — మార్పులు working tree లో ఉన్నాయి.

---

## 1. సారాంశం

| వర్గం | సంఖ్య |
|---|---|
| 🔴 ముఖ్యమైనవి (Play Store / Razorpay అడ్డంకులు) | 5 |
| 🟠 మధ్యస్థం | 6 |
| 🟡 చిన్నవి / శుభ్రత | 7 |
| ఆటోమేటిక్‌గా చేసిన ఫిక్స్‌లు | 1 (లింక్‌లు) + 1 test |

**అత్యంత ముఖ్యమైన 5:**
1. 🔴 **మూడు యాప్‌లలో (యూజర్/వెండర్/స్టాఫ్) Privacy/Terms లింకే లేదు**, సైన్అప్‌లో అంగీకార checkbox లేదు, అంగీకారం ఎక్కడా సేవ్ కావడం లేదు. → లింక్‌లు జోడించాను (§7). Checkbox + సేవ్ చేయడం auth మార్పు కాబట్టి **అప్రూవల్ కావాలి** (#1).
2. 🔴 **Terms / Refund / Pricing / Contact పేజీలు ఇంకా deploy కాలేదు**, మరియు `ai-care` లో ఉన్న కాపీలలో ఇంకా **`XX`** ఉన్నాయి. నిజమైన వివరాలతో ఉన్న వెర్షన్ `razorpay-site` బ్రాంచ్‌లో (`d5f1a42`). యాప్‌లలో నేను జోడించిన లింక్‌లు deploy వరకు సరైన పేజీ చూపవు (#2).
3. 🔴 **Privacy Policy లలో Razorpay గురించి, AI (Flash chats టెక్స్ట్ Anthropic కి వెళ్లడం) గురించి ఏమీ లేదు** (4 పేజీల్లో 0 ప్రస్తావనలు). Play Data safety కూడా నవీకరించాలి (#3).
4. 🔴 **Delivery/Shipping పాలసీ పేజీ లేదు.** Razorpay తరచూ అడుగుతుంది (డిజిటల్ సర్వీస్ అయినా "వర్తించదు" అని చెప్పే పేజీ కావాలి) (#4).
5. 🔴 **Razorpay keys ఇంకా సెట్ కాలేదు**, functions deploy కాలేదు → వెండర్లు పే చేయలేరు (§6).

---

## 2. భాగాల వారీగా

### 2.1 వెబ్‌సైట్ (`web/`)
- ✅ Privacy: `/privacy`, `/privacy-vendor`, `/privacy-staff`, `/privacy-policy`, `/delete-account` ఉన్నాయి.
- ⚠️ Terms, Refund, Pricing, Contact: `web/` లో ఉన్నాయి కానీ **git లో tracked కావు** (untracked) మరియు `XX` ఉన్నాయి (`contact/index.html:43,45,46`, `pricing/index.html:44`, `terms/index.html:38,104,107`).
- ⚠️ **locamarket.in Hostinger లో ఉంది** — `firebase.json` rewrites అక్కడ పనిచేయవు. `razorpay-site` బ్రాంచ్‌లో `.htaccess` ఫిక్స్ ఉంది (`/privacy-policy` హోమ్‌పేజీకి వెళ్లడం).
- ⚠️ వెబ్‌సైట్ హోమ్ పేజీలో policy లింక్‌ల వరుస `razorpay-site` లో మాత్రమే (`HomeSiteLinks`), ఈ బ్రాంచ్‌లో లేదు.
- Delivery policy పేజీ: ❌ లేదు.
- `delete-account.html` = `delete-account/index.html` (byte-identical).

### 2.2 వెండర్ యాప్ (`main_vendor.dart`, flavor `vendor`, `in.locamarket.vendor`)
- ❌ UI టెక్స్ట్ 158 చోట్ల (ఫైల్స్ 48), **అనువాదం కేవలం 7 చోట్ల** → దాదాపు పూర్తిగా ఇంగ్లీష్ మాత్రమే.
- ❌ సైన్అప్‌లో Terms/Privacy అంగీకార checkbox లేదు; `vendor_registration_form.dart` లో కూడా లేదు.
- ✅ (కొత్త) సైన్-ఇన్ లో Privacy/Terms/Refund/Contact లింక్‌లు.
- Razorpay ఫ్లో: పే బటన్, "I have paid" చెక్ ఉన్నాయి.

### 2.3 స్టాఫ్ యాప్ (`main_field.dart`, flavor `staff`, `in.locamarket.staff`)
- ❌ UI టెక్స్ట్ 113 చోట్ల, **అనువాదం 0**.
- ❌ అంగీకార checkbox లేదు.
- ✅ (కొత్త) సైన్-ఇన్ లో Privacy (staff) / Terms / Contact లింక్‌లు.
- 🟡 పేరు అసమానత: hosting target `field`, ఫైల్ `main_field.dart`, యాప్ title "Field Assistant", Android పేరు "S Loca Market", ప్యాకేజీ `staff`.

### 2.4 యూజర్ యాప్ (`main.dart`, flavor `customer`, `in.locamarket.locamark`)
- ✅ అనువాద వ్యవస్థ ఉంది (`.tr(context)` 195 చోట్ల, 10 భాషలు).
- ❌ **36 లేబుల్స్‌కి తెలుగు లేదు** (§5).
- ❌ సైన్అప్ అంగీకార checkbox లేదు.
- ✅ (కొత్త) సైన్-ఇన్ లో Privacy/Terms/Contact లింక్‌లు.
- ⚠️ Play లింక్ ఇంకా 404 (యాప్ review/testing లో).

### 2.5 అడ్మిన్ ప్యానెల్ (`main_admin.dart`, hosting `admin`)
- UI టెక్స్ట్ 384 చోట్ల, అనువాదం 0 (అడ్మిన్ ఇంగ్లీష్ మాత్రమే అయితే సమస్య కాదు; మీ నిర్ణయం).
- ✅ Payments ట్యాబ్: Razorpay on/off + తాజా చెల్లింపులు.
- ✅ Ads ట్యాబ్: Who sees it + categories + "Vendors see views" switch.

---

## 3. డూప్లికేట్ ఫైల్స్

| ఫైల్స్ | వివరం | సూచన |
|---|---|---|
| `web/delete-account.html` ↔ `web/delete-account/index.html` | byte-identical | `/delete-account` రెండూ వాడవచ్చు; ఒకటి ఉంచండి (Play Console లో ఏ URL ఇచ్చారో చూడండి), మరొకటి తర్వాత తీయవచ్చు |
| `web/privacy-policy.html` ↔ `web/privacy/index.html` | దాదాపు ఒకటే (25 లైన్ల తేడా; పాత పేరు "Local Market") | `/privacy-policy` URL లింక్‌లలో వాడుతున్నారు కాబట్టి **ఉంచండి**; ఒకే మూలం నుంచి generate అయ్యేలా (`scripts/build-privacy-pages.cjs`) చేయడం మంచిది |
| `functions/data/places.*.v1.json` ↔ `web/data/places.*.v1.json` | 37 + 37 ఫైల్స్, ఒకే కంటెంట్ | ఉద్దేశపూర్వకం (సర్వర్ + వెబ్ రెండూ వాడతాయి). ఒక build స్టెప్ లో copy చేయండి, కానీ తీయకండి |
| `android/app/src/debug/AndroidManifest.xml` ↔ `.../profile/...` | identical | Flutter default, ఉంచండి |
| `ios/Flutter/Debug.xcconfig` ↔ `Release.xcconfig` | identical | default, ఉంచండి |
| `ios/Runner.xcworkspace/...WorkspaceSettings.xcsettings` ↔ `ios/Runner.xcodeproj/...` | identical | default, ఉంచండి |

---

## 4. అవసరం లేని (వాడని) ఫైల్స్ — **డిలీట్ చేయలేదు, జాబితా మాత్రమే**

4 entry points నుంచి import graph తో కొలిచాను (309 Dart ఫైల్స్ లో 15 unreachable; 5 conditional-import `_web/_io` ఫైల్స్ false positives, అవి వాడుతున్నాయి).

| ఫైల్ | కారణం | డిలీట్ చేస్తే |
|---|---|---|
| `lib/ui/offers_ads_page.dart` | ఏ చోటా import లేదు, test లేదు (44 లైన్లు) | సురక్షితం |
| `lib/ui/home_quick_category_nav.dart` | ఎక్కడా import లేదు | సురక్షితం |
| `lib/ui/home_categories_section.dart` | `wireframe_home.dart` లో కామెంట్ మాత్రమే; import లేదు | సురక్షితం |
| `lib/ui/home_category_tile.dart`, `lib/ui/home_shop_tile.dart` | `home_widgets.dart` barrel ద్వారా మాత్రమే (అది కూడా dead) | barrel తో కలిపి |
| `lib/ui/home_widgets.dart` | barrel; tests మాత్రమే వాడతాయి (`home_layout_test`, `modularity_test`) | tests ను ముందు మార్చాలి |
| `lib/ui/vendor.dart` | barrel; tests మాత్రమే (`vendor_test`, `vendor_registration_gps_test`) | tests ను ముందు మార్చాలి |
| `lib/ui/home_ad_rail.dart` (274 లైన్లు) | యాప్ కోడ్ లో కామెంట్ మాత్రమే; `home_ad_rail_test.dart` మాత్రమే వాడుతుంది | test తో కలిపి |
| `lib/domain/category_images.dart` | `home_category_tile.dart`+`category_photos_test` మాత్రమే | పై వాటితో కలిపి |
| `lib/modules/premiumadmin/premiumadmin_module.dart` | route const మాత్రమే, ఎవరూ import చేయరు | module pattern కోసం ఉంచాలేమో; మీ నిర్ణయం |
| `pubspec.yaml: cupertino_icons` | ఎక్కడా import/`CupertinoIcons` లేదు | ప్యాకేజీ మార్పు → అప్రూవల్ |

**పాత one-off స్క్రిప్ట్‌లు (`scripts/`):** `fix-ad-box-height.cjs`, `fix-ad-box-heights.cjs`, `fix-ad-boxes-static-and-ticker-direction.cjs`, `fix-rail-gap-and-ticker.cjs`, `seed-ad-routing-and-scroll-fix.cjs`, `set-compact-density.cjs`, `delete-stray-rice-product.cjs`, `decouple-notice.cjs`, `seed-new-reference-updates.cjs`, `seed-reference-design-extras.cjs` — పేర్లను బట్టి ఒకసారి నడిపిన మైగ్రేషన్లు. (నడిపి ఉన్నాయో లేదో నేను నిర్ధారించలేను.)

**Git లో లేని స్థానిక చెత్త (gitignored, repo కి హాని లేదు):** `tmp/` 861 MB, `output/` 278 MB (572 ఫైల్స్), `website-images/` 51 MB, `category-icons/` 20 MB, రూట్ లో ~25 `*.log` ఫైల్స్. డిస్క్ ఖాళీ చేయాలంటే తీయవచ్చు.
**చిన్నది:** `locamarket_products.csv`, `web_admin_overlay/` (8 ఫైల్స్, `scripts/build-admin-web.ps1` వాడుతుంది) — ఉంచండి.
`tools/sms-forwarder/` git నుంచి తీసేశాను (Razorpay కి మారినప్పుడు); స్థానిక build ఫైల్స్ ఇంకా ఉండవచ్చు.

---

## 5. మిస్ అయిన లేబుల్స్ మరియు పాలసీ పేజీలు

**అనువాదం కవరేజ్ (`.tr()`):**

| యాప్ | UI టెక్స్ట్ | `.tr()` | తెలుగు లేనివి |
|---|---|---|---|
| యూజర్/shared | 340 | 195 | **36** |
| వెండర్ | 158 | 7 | 0 |
| స్టాఫ్ | 113 | 0 | 0 |
| అడ్మిన్ | 384 | 0 | 0 |

యూజర్ యాప్ లో తెలుగు లేని లేబుల్స్ (నేను జోడించలేదు — ప్రతి అనువాదం 10 భాషల వరుసగా ఉండాలి, తప్పుడు అనువాదాలు సృష్టించకూడదని; అప్రూవల్ #5):
`sign_in_panel.dart`: Continue with Google, Send me a code, Verify and sign in, 6-digit code, Enter a valid email address., Enter the 6-digit code., Sign-in failed…, Something went wrong…, Google sign-in did not work…, No Google account? Use an email code, Hide the email code option, Use a different email…, We sent a 6-digit code…
`responsive_header_bar.dart` / `android_home_header.dart`: Become a Seller, Notifications, Menu, Hello {name}, Nothing saved yet.
`home_*`: All, {count} matching items, Add {name} to bag, {percent}% OFF, Today's Best Offers in {location}, Today's {town} Offers, your area, Book trusted help near you, Services will appear here when available., Show promotion {n}
`account.dart`, `account_auth_form.dart`, `place_search_box.dart` (State), `transport_page.dart` (Transport).
పూర్తి జాబితా: స్క్రాచ్‌ప్యాడ్ `tr_missing.txt`.

> గమనిక: Google/email-code సైన్-ఇన్ టెక్స్ట్‌లే వెండర్/స్టాఫ్ యాప్‌లలోనూ కనిపిస్తాయి (shared `SignInPanel`), కాబట్టి ఇవి తెలుగు లేకపోవడం మూడు యాప్‌లను ప్రభావితం చేస్తుంది.

**పాలసీ పేజీల పట్టిక:**

| పేజీ | వెబ్‌సైట్ | యూజర్ యాప్ | వెండర్ | స్టాఫ్ |
|---|---|---|---|---|
| Privacy Policy | ✅ | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) |
| Terms & Conditions | ⚠️ XX, deploy కాలేదు | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) |
| Refund & Cancellation | ⚠️ deploy కాలేదు | — (వర్తించదు) | ✅ లింక్ (కొత్త) | — |
| Delivery / Shipping | ❌ లేదు | ❌ | ❌ | ❌ |
| Contact / Support | ⚠️ XX, deploy కాలేదు | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) | ✅ లింక్ (కొత్త) |
| Account deletion | ✅ | — | — | — |
| **సైన్అప్ అంగీకార checkbox** | — | ❌ | ❌ | ❌ |
| **అంగీకారం సేవ్ (termsAccepted…)** | — | ❌ | ❌ | ❌ |

---

## 6. పేమెంట్ గేట్వే (Razorpay) స్థితి

**కోడ్ సిద్ధం (కమిట్ `36c73ef`):**
- ✅ Payment Link సృష్టి (`startRazorpayPayment`), మొత్తం server లోనే ప్లాన్ ధర నుంచి (క్లయింట్ మొత్తం పంపలేడు), part payment నిషేధం.
- ✅ **సక్సెస్:** signed webhook `razorpayWebhook` (HMAC-SHA256, raw body) + "I have paid" చెక్; payment id ఒక్కసారే వాడగలరు (transaction); మొత్తం, link id, request id సరిపోవాలి.
- ✅ **రద్దు:** request cancel అయితే link cancel; ఆ తర్వాత చెల్లింపు వస్తే `paid_after_cancel` + వెండర్‌కు నోటీసు.
- ✅ **సీక్రెట్లు:** కోడ్ లో హార్డ్‌కోడ్ లేదు (secrets: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`). tracked ఫైల్స్ అన్నింటిలో API key/private key/token patterns స్కాన్ చేశాను: **ఏదీ దొరకలేదు.** keystore, `key.properties`, `google-services.json` git బయట ఉన్నాయి.
- ✅ tests: 847 app tests పాస్, 234/235 server tests పాస్ (1 ముందే ఉన్న వైఫల్యం, Quick Add "outside Andhra").

**లోపాలు / ఇంకా లేనివి:**
- ❌ **Keys సెట్ కాలేదు, functions deploy కాలేదు, webhook Razorpay లో జోడించలేదు** → వెండర్లు పే చేయలేరు (అప్పటివరకు "Payments will open soon").
- ⚠️ **రిఫండ్ ఫ్లో కోడ్ లో లేదు** — Razorpay dashboard నుంచి చేతితో చేయాలి (`payment.refunded` webhook వినడం లేదు, కాబట్టి రిఫండ్ చేసినా ప్లాన్ ఆగదు). అప్రూవల్ #6.
- ⚠️ **Failed payment:** `payment.failed` ఈవెంట్ వినడం లేదు; link 2 రోజుల్లో expire అవుతుంది, వెండర్ మళ్లీ ప్రయత్నించవచ్చు. పని చేస్తుంది కానీ వెండర్‌కు "failed" సందేశం ఉండదు.
- ⚠️ Razorpay ఖాతా KYC/website అప్రూవల్ కోసం: Terms, Refund, Pricing, Contact deploy కావాలి (§2.1), delivery policy (§5), Privacy లో Razorpay.
- Play Store: Data safety లో "Payments / Financial info" Razorpay ద్వారా అని నవీకరణ; మీ ఖాతా డేటా (కార్డు వివరాలు) మీరు ఉంచుకోరని పేర్కొనాలి.

---

## 7. ఆటోమేటిక్‌గా చేసిన మార్పులు

1. **కొత్త ఫైల్ `lib/ui/policy_links.dart`** — Privacy Policy (యాప్ వారీగా `/privacy`, `/privacy-vendor`, `/privacy-staff`), Terms, Refund (వెండర్ మాత్రమే), Contact లింక్‌లు (`https://locamarket.in/...`, బయటి బ్రౌజర్‌లో).
2. **`lib/ui/sign_in_panel.dart`** — import (`:8`) మరియు `PolicyLinks(appRole: widget.store.appRole)` (`:150`, సైన్-ఇన్ progress bar తర్వాత). ఈ ఒక్క panel మూడు యాప్‌లు వాడుతున్నాయి కాబట్టి మూడింటిలోనూ కనిపిస్తుంది.
3. **కొత్త test `test/policy_links_test.dart`** — ప్రతి యాప్ సరైన privacy పేజీకి వెళ్తోందో, లింక్ చేసిన పేజీలు `web/` లో ఉన్నాయో చూస్తుంది.

తనిఖీ: `flutter analyze lib test` → **0 errors, 0 warnings** (13 info మాత్రమే); కొత్త tests 2/2 పాస్.
⚠️ లింక్‌లు Terms/Refund/Contact పేజీలు deploy అయ్యేవరకు సరైన పేజీ చూపవు.
ఈ మార్పులు కమిట్ చేయలేదు (`git diff` తో చూడవచ్చు; వెనక్కి వెళ్లాలంటే `audit-backup`).

**ఇతర స్కాన్ ఫలితాలు (మార్పు లేదు):** `print()` 0; TODO/FIXME 0; `catch (_)` 63 చోట్ల (ఎక్కువ ఉద్దేశపూర్వక "best effort": analytics, ad tracking, link open). Android permissions: INTERNET, POST_NOTIFICATIONS, ACCESS_FINE/COARSE_LOCATION — వెండర్/స్టాఫ్ flavors కూడా main manifest వల్ల location అడుగుతాయి; వాటికి అవసరమా అని Play Data safety లో చూడండి.

---

## 8. నా అప్రూవల్ కావాల్సినవి (నంబర్లతో)

1. **సైన్అప్ అంగీకార checkbox** (యూజర్/వెండర్/స్టాఫ్) + అంగీకారం (తేదీ, వెర్షన్) సేవ్ చేయడం — auth/DB మార్పు.
2. **`razorpay-site` ని merge + deploy**: Terms/Refund/Pricing/Contact (నిజమైన వివరాలతో), హోమ్ policy వరుస, `.htaccess` ఫిక్స్ → Hostinger + Firebase hosting. (`ai-care` లోని untracked XX కాపీలు ముందు తొలగించాలి.)
3. **Privacy Policy 4 పేజీలలో** Razorpay + AI (Flash చాట్ టెక్స్ట్ Anthropic కి) చేర్చడం; Play **Data safety** నవీకరణ.
4. **Delivery/Shipping policy పేజీ** సృష్టి (`web/shipping-policy/` + firebase.json rewrite + లింక్‌లు).
5. **యూజర్ యాప్ 36 లేబుల్స్ అనువాదాలు** (10 భాషలు, `strings_details.dart`) — మీరు తెలుగు పరిశీలించి ఓకే చెప్తే జోడిస్తాను. + వెండర్/స్టాఫ్ యాప్‌లను తెలుగులోకి తీసుకురావాలా అనే నిర్ణయం (పెద్ద పని: 270+ టెక్స్ట్‌లు).
6. **రిఫండ్ + failed payment webhooks** (`payment.refunded`, `payment.failed`) — పేమెంట్ లాజిక్ మార్పు.
7. **Razorpay keys సెట్ + functions deploy + webhook జోడింపు** (deploy మీదే).
8. **డిలీట్ చేయవచ్చు** (§4 పట్టిక): `offers_ads_page.dart`, `home_quick_category_nav.dart`, `home_categories_section.dart` (సురక్షితం); `home_widgets.dart`/`vendor.dart` barrels, `home_category_tile.dart`, `home_shop_tile.dart`, `home_ad_rail.dart`, `category_images.dart` (వాటి tests తో కలిపి).
9. **పాత స్క్రిప్ట్‌లు** (§4) తీయడం.
10. **`web/delete-account.html`** లేదా `/delete-account/index.html` లో ఒకటి తీయడం (Play Console లో ఏ URL ఉందో చెప్పండి).
11. **`cupertino_icons`** ప్యాకేజీ తీయడం (pubspec మార్పు).
12. **స్థానిక చెత్త శుభ్రం:** `tmp/` (861 MB), `output/` (278 MB), రూట్ `*.log` ఫైల్స్.
13. **స్టాఫ్ యాప్ పేరు ఏకరూపం** ("Field Assistant" vs "S Loca Market" vs hosting `field`).
14. **వెండర్/స్టాఫ్ యాప్‌ల నుంచి location permission** తీయడం (అవసరం లేకపోతే) — Android manifest మార్పు.
15. **ముందే విఫలమవుతున్న server test** `quick-items.test.js` ("outside Andhra") సరిచేయడం.

---

## 9. ప్రాధాన్యత క్రమం — ముందు ఏం చేయాలి

1. **#2** `razorpay-site` merge + deploy (Razorpay ఖాతా అప్రూవల్ కి ఇదే మొదటి అడ్డంకి).
2. **#4** Delivery policy + **#3** Privacy లో Razorpay/AI.
3. **#1** అంగీకార checkbox (Play + చట్టపరమైన రక్షణ).
4. **#7** Razorpay keys + functions deploy + webhook → పేమెంట్లు తెరవడం.
5. **#6** రిఫండ్/failed webhooks.
6. **#5** తెలుగు అనువాదాలు.
7. **#8–#15** శుభ్రత (ఎప్పుడైనా).
