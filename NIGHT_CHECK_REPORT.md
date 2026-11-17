# NIGHT CHECK REPORT (11–12 Nov 2026)

నియమాలు: అసలు app code మార్చలేదు, deploy చేయలేదు, commit చేయలేదు. కొత్త tests `test/night_check/` లో మాత్రమే.
గుర్తులు: **[RUN]** = నిజంగా నడిపి ధృవీకరించినది (test / emulator / browser). **[CODE]** = కోడ్ చదివి మాత్రమే.

---

## 0. పూర్తి జాబితా (code నుంచి)

### 0.1 అడ్మిన్ ప్యానెల్ (వెబ్ `/admin`, lib/ui/admin.dart)
పై tabs: Insights, Orders, Products, Vendors (Vendors / Service providers / Quick Add accounts / Quick Add items), Shops, Complaints, Promotions, Plans, Vendor Offers, Premium, Payments, Flash, Staff Areas, Settings. పైన బటన్లు: Search, AI Agent, Sign out.

Settings sections (lib/ui/admin_settings.dart):
| # | Section | Firestore |
|---|---|---|
| S1 | Categories | `categories` |
| S2 | Services | `services` |
| S3 | Field Assistants | `fieldAssistants` (approve/suspend) |
| S4 | City codes | `settings/cityCodes.rows` |
| S5 | Business Profile | `settings/business` (31 fields) |
| S6 | Theme | `settings/theme` (22 fields) |
| S7 | Animations | `settings/animations` |
| S8 | Scrolling Text | `settings/scrollingText` (30 fields) |
| S9 | Today's Offers (banner) | `settings/section_notice` |
| S10 | Today's Offers Box | `promotions` (placement carousel) + item offers (placement todayOffer) |
| S11 | Fresh Fruits & Vegetables | `settings/freshStrip` |
| S12 | Shops without location | `shops` (latitude/longitude) |
| S13 | Right Side Ads | `ads` + `adsPrivate` + `settings/adsConfig` |
| S14 | Right Side Ad Boxes | `settings/rightAdBoxes` |
| S15 | Product Image Library | `productImageLibrary` |
| S16 | Layout (Layout settings / Visual Editor / Page view) | `settings/section_*`, `settings/my_default` |
| S17 | Android App | `settings/androidHome`, `settings/androidSizes` |
| S18 | Quick Add locations | `locations` |
| S19 | Sample data | records labelled SAMPLE |
| S20 | Area names | `settings/areaNames` (renames, blocked) |
| S21 | Transport (module) | module docs |
| S22 | Item photos (module) | `vendorItemPhotos`, `vendorShopPhotos`, `categories` |
Module tabs: Plans (`planServiceGates/main`, plans), Vendor Offers (`vendorOffersConfig/main`, `vendorOffers`), Premium (`vendorTodaysOffers`, `wholesaleOffers`), Payments (`paymentSettings/main`, `paymentRequests`, `paymentPublic/main`), Flash (`flashPublic/main`, `flashTickets`, `messages`), Staff Areas (`staffAreaSettings/main`, `staffAreas`, `staffAreaTowns`, `staffAreaHolders`).
Insights: analytics (people/reports), push centre (`settings/business` switches), inactive accounts (`settings/inactiveAccounts`), setup check, staff report, ad reports.

### 0.2 వెబ్‌సైట్ + యూజర్ Android app (ఒకే code: lib/main.dart → Storefront)
Bottom nav: Home, Categories, Shops, Account. Home: header (logo, tagline, greeting, location box, search + voice + camera, wishlist, bag, office, Become a Seller, languages), Scrolling Text, Today's Offers banner (chips), Today's Offers Box (6 boxes / Android 2), Fresh strip, Popular products, Local Services, Nearby shops, Right Side Ad Boxes (web) / ads strip (Android), Quick fresh items, footer badges. Pages: product, category, shop, shop route map, item "where to buy", product search near me, services, cart/checkout, account (sign-in, consent, alerts, language, logout), location picker, first-open sign-in sheet, Flash chat.

### 0.3 వెండర్ app (lib/main_vendor.dart)
Sign-in (Google / email code), "Vendor or Service provider?", home (Vendor / Services / Transport), registration form (shop GPS, photos), workspace: products, orders, requests, kit, exclusives, shop photos, shop ad (right box), My Ads, plans + payment, premium Today's Offer, vendor offers, showcase, wholesale, switch role, logout.

### 0.4 స్టాఫ్ app (lib/main_field.dart)
Sign-in, registration (name, phone, photo), area claim / auto area (live 100 m photos), waiting for approval, workspace: Add (link a vendor or service), field entry form, quick add, staff links, staff report, logout.

### 0.5 Server (functions/) — role logins, email code, orders, notifications, vendor ads, shop ads, plans, payments, flash, staff areas, inactive accounts, image checks.

---

## 1. ఫలితాలు (పని జరుగుతున్న కొద్దీ ఇక్కడ జోడిస్తాను)

### 1.1 Admin fields → ఎవరు చదువుతారు (177 fields, automatic cross-reference) [CODE]
Script: ప్రతి field పేరు (lib/ui/admin_fields.dart) ని admin కాని lib files లో, functions/ లో వెతికింది. పూర్తి list: session temp `night/xref.txt`.
- **ఎక్కడా చదవని fields (పని చేయవు):**
  - `settings/business.directVendorPaymentInstructions`: Business Profile లో form ఉంది, కానీ app, website, server ఏదీ చదవదు. Checkout లో కనిపించదు.
  - `settings/scrollingText.noticeType`: Scrolling Text form లో ఉంది, ఎవరూ చదవరు.
- **Promotions లో పాత "ad rail" కోసం మాత్రమే ఉన్న fields (ఆ rail page నుంచి తీసేశారు, file dead):** `width`, `spacing`, `position`, `scrollEnabled`, `stopAfter`. వీటిని `home_ad_rail.dart` / `ScheduledPromo` మాత్రమే చదువుతాయి, ఆ widget ఏ page లోనూ వాడటం లేదు → admin లో మార్చినా ఏమీ మారదు. (`direction`, `speed` carousel కి వాడుతున్నారు: wireframe_home.dart.)
- Admin లో మాత్రమే వాడేవి (సరైనవే): `storageWarningGb` (Insights), `notifySubscribers` / `autoPublishVendorChanges` / `priceDropAutoEnabled` / `exclusiveExpiryNoticeDays` (server functions చదువుతాయి).
- మిగతా fields అన్నీ కనీసం ఒక app file లేదా server function లో చదువుతున్నారు.

### 1.2 వాడని files (ఏ app entry point నుంచీ చేరవు) [CODE]
`lib/ui/home_ad_rail.dart`, `lib/ui/home_scheduled_promo.dart` (ad rail లో మాత్రమే), `lib/ui/offers_ads_page.dart` ("Offers & Ads" page: ఏ బటన్ నుంచీ తెరవరు), `lib/ui/home_categories_section.dart`, `lib/ui/home_category_tile.dart`, `lib/domain/category_images.dart`, `lib/ui/home_quick_category_nav.dart`, `lib/ui/home_shop_tile.dart`, `lib/ui/home_widgets.dart`, `lib/modules/premiumadmin/premiumadmin_module.dart`, `lib/ui/vendor.dart` (tests మాత్రమే import చేస్తాయి). Dead helpers: `promotionsForTown` / `promotionReaches` / `coveringCustomer` (towns.dart, radius.dart), `LocationTargetField`, `GeoTargetPicker` (offer form నుంచి తీసేశాక), `Store.completePlace`, `Store.productTown`.
(`*_web.dart` / `*_io.dart` files conditional imports తో వాడుతున్నారు, అవి dead కావు.)

### 1.3 వెబ్‌సైట్ build [RUN]
`flutter build web --release -t lib/main.dart` (production config) → **విజయవంతం**, 138 s, 71 MB (session temp `night/web-customer`). Production కి connect అయ్యే ఈ build ను తెరవలేదు (production analytics కలుషితం కాకుండా); emulator build తో నడిపాను (క్రింద 1.x).

### 1.4 Admin forms: ప్రతి field save అవుతుందా [RUN] (test/night_check/admin_form_roundtrip_test.dart)
అసలు admin form (EntryEditor) లో ప్రతి text field లో value టైప్ చేసి "Save changes" నొక్కి, record లో అదే field పేరుతో అదే value ఉందో చూశాను. 10 forms: products, services, locations, productImageLibrary, categories, shops, promotions, settings (Business Profile), scrollingText, theme.
- **139/139 text fields OK**: ప్రతిదీ సరైన collection, సరైన field పేరుతో save అయింది (theme, scrollingText → `settings/theme`, `settings/scrollingText`; Business Profile → `settings/business`).
- 38 fields test చేయలేదు (text box కాదు): dropdowns (placement, categoryId, shopId, radiusShopId, defaultPaymentMethod, notifySubscribers, mode, position, scrollEnabled, fontWeight), colour pickers (`*Color`), date pickers (startsAt/endsAt).
- Form నియమాలు [RUN]: products/services/productImageLibrary కి category తప్పనిసరి ("Choose a Category"); pincode 6 అంకెలు తప్పనిసరి; promotions కి shop తప్పనిసరి. ఇవి సరిగ్గా పని చేస్తున్నాయి.

### 1.5 అడ్మిన్ మార్పు → వెబ్‌సైట్ / యూజర్ app లో కనిపిస్తుందా [RUN] (test/night_check/admin_to_customer_test.dart)
అసలు MarketApp (demo store) ని వెబ్ వెడల్పు (1440) తో, Android మోడ్ (390) తో నడిపాను. Admin save చేసే records పెట్టి, screen పై text కోసం వెతికాను.
| Check | Website | Android app |
|---|---|---|
| Business Profile `tagline` | ✅ | ❌ కనిపించదు (Android header లో tagline లేదు: design ప్రకారం) |
| Business Profile `headerContact` | ✅ | ❌ కనిపించదు (Android header లో contact box లేదు) |
| Scrolling Text `text` | ✅ | ✅ |
| Greeting "Hello, Kancharapalem People" | ✅ | ✅ |
| Location box = ఏరియా పేరు | ✅ | ✅ |
| Banner "Today's Kancharapalem Offers" | ✅ | ✅ |
| km లోపు shop offer (`promotions.radiusShopId`) | ✅ | ✅ |
| Shop లేని offer దాగుతుంది | ✅ | ✅ |
| km లోపు shop product | ✅ | ✅ |
| దూరపు shop product దాగుతుంది | ✅ | ✅ |
| `noOffersMessage` ({town} = ఏరియా) | ✅ | ✅ |

### 1.6 Server functions + Firestore/Storage rules tests [RUN] (emulator)
`firebase emulators:exec --only firestore,storage,auth "cd functions && npm test"` → **326/326 pass**, 0 skip.
గమనిక: storage.rules line 6 (`request.auth.token.role in [...]`) role లేని login కి "Property role is undefined" warning (6 సార్లు) ఇస్తుంది; ఫలితం deny (fail-closed), హాని లేదు. శుభ్రంగా ఉండాలంటే `'role' in request.auth.token &&` ముందు పెట్టవచ్చు.

### 1.7 రోల్ ఆధారిత access [RUN] (test/night_check/rules_night.test.cjs, emulator)
7 రకాల logins (anonymous, role లేని email login, user, vendor, staff, OTP లేని admin, admin) × settings/business, settings/areaNames, products, promotions, ads, adsPrivate, users, orders, roleLogins → **74/74 ఆశించినట్లే**:
- vendor / staff / user / anonymous / role లేని login / OTP లేని admin: settings, products, promotions, ads **మార్చలేరు**; ఇతరుల `users/*`, `orders/*`, `adsPrivate`, `roleLogins` **చదవలేరు**; `users` list చేయలేరు; products delete చేయలేరు.
- vendor ఇంకో vendor record మార్చలేడు. User తన `users/{uid}` మాత్రమే చదవగలడు.
- Anonymous: settings, products చదవగలడు (public catalogue, సరైనదే).
- Admin (OTP session తో): settings, areaNames రాయగలడు; users చదవగలడు; `roleLogins` (server-only) చదవలేడు.

### 1.8 వెబ్‌సైట్ నిజంగా browser లో [RUN] (emulator, headless Chrome)
విధానం: `-o night/web-emu` build (USE_EMULATORS=true, project demo-neighbourly, production తాకలేదు) → Firestore emulator లో seed (business, scrollingText, areaNames, 2 shops, 2 products, 2 offers) → `python -m http.server 5055` → Chrome DevTools protocol తో GPS ఇచ్చి/నిరాకరించి 40 s తర్వాత screenshot + localStorage. Scripts, screenshots: session temp `night/` (shot-1..4).
| పరిస్థితి | ఫలితం |
|---|---|
| 1. GPS అనుమతి, Kancharapalem PO point (17.734, 83.279), desktop 1400 | ✅ మొదట తెరవగానే అనుమతి అడిగి లొకేషన్ save (`flutter.area`, `latitude`, `followsGps=true`, `locationAsked=true`). Greeting "Hello, **Boyapalem** People", location box "Boyapalem", banner "Today's Boyapalem Offers", NIGHT NEAR OFFER ✅, shop లేని offer దాగింది ✅, దగ్గరి product ✅, దూరపు product దాగింది ✅, Nearby shops "Kancharapalem Kirana 0.2 km" ✅, tagline, header contact, scrolling text ✅. |
| 2. అదే, mobile web 390 | ✅ అదే విధంగా. |
| 3. GPS నిరాకరణ | ✅ వెంటనే "Where are you shopping?" picker (Use my location, State, search, pincode, delivery address, place name, pin). ఏ లొకేషన్ save కాలేదు, "Choose your location to see the offers near you." ✅ |
| 4. GPS New Delhi (28.61, 77.21) | ✅ "Hello, Raisina Hill People", "NIGHT no offers near Raisina Hill" (admin message), ఏ offer/product లేదు ✅ |

గమనించిన సమస్యలు (నిజంగా చూసినవి):
- **ఏరియా పేరు ఖచ్చితత్వం:** Kancharapalem post office GPS వద్ద OpenStreetMap "Boyapalem" అని ఇచ్చింది. పేరు OSM data పై ఆధారపడుతుంది. Admin → Settings → Area names లో "Boyapalem = Kancharapalem" లాగా సరిచేయవచ్చు, లేదా ఆ ప్రాంతానికి OSM data ను పరిశీలించాలి. (మధ్యస్థం)
- **మొదటిసారి రెండు popups ఒకేసారి:** "Welcome to LOCAMARKET" sign-in sheet, location picker (GPS నిరాకరిస్తే) ఒకదానిపై ఒకటి వస్తాయి (shot-3). (తక్కువ)
- దగ్గర్లో products లేనప్పుడు "No matching products. Try another search." అని వస్తుంది, కానీ customer ఏమీ search చేయలేదు. పాత "You can change your pincode without enabling GPS." వాక్యం Nearby shops లో ఇంకా ఉంది. (తక్కువ, wording)
- ఖాళీ Right Side Ad Boxes లో "ఇక్కడ మీ ప్రకటన" తెలుగులో వస్తుంది, ఇంగ్లీష్ భాషలో కూడా. (తక్కువ)

### 1.9 ప్రతి admin screen తెరుచుకుంటుందా [RUN] (test/night_check/screens_open_test.dart)
- **Admin tabs 14/14 తెరుచుకున్నాయి**: Insights, Orders, Products, Vendors, Shops, Complaints, Promotions, Plans, Vendor Offers, Premium, Payments, Flash, Staff Areas, Settings. Firebase అవసరమైనవి demo లో "Connect Firebase" సందేశం చూపిస్తాయి (crash లేదు).
- **Settings sections desktop లో 21/22 తెరుచుకున్నాయి.**
- ❌ **"Item photos" section (lib/modules/photolimits/admin_item_photos.dart) Firebase లేకుండా crash అవుతుంది:** `[core/no-app] No Firebase App '[DEFAULT]'`. ఇది నేరుగా `FirebaseFirestore.instance` వాడుతుంది, మిగతా sections లాగా `AdminNeedsFirebase` / `store.live` check లేదు. Live admin panel లో సమస్య లేదు (Firebase ఉంటుంది). Demo/preview లో మాత్రమే. (తక్కువ)
- Phone (390 px): మొదటి 12 sections తెరుచుకున్నాయి. మిగతావాటికి test list ను scroll చేయలేకపోయింది. ఇది test పరిమితి; desktop లో అవే sections తెరుచుకున్నాయి.
- Scrolling Text section లో preview నిరంతరం కదులుతుంది. ఇది సరైనదే.

### 1.10 Login / logout / ఫోటో upload / notifications / ఏరియా శోధన
| Feature | ఎలా చూశాను | ఫలితం |
|---|---|---|
| Google sign-in (one tap), email code, agreement sentence | [RUN] test/google_one_tap_test, email_auth_test, first_open_sign_in_test, consent_test (942-suite లో) + functions email-login tests (emulator) | ✅ pass |
| Role logins (enterRole / switchRole), vendor ↔ provider | [RUN] functions role-logins tests (emulator) + vendor_home_test | ✅ pass |
| Admin login (password + OTP, session) | [RUN] admin_auth_test + functions admin-otp tests + rules (OTP session లేని admin deny) | ✅ pass |
| Logout | [RUN] email_auth_test, vendor_home_test, admin_auth_test (logout తర్వాత Google ఆటో sheet మళ్ళీ రాదు) | ✅ pass |
| Play review code (playreview.*) | [RUN] functions email-login test (emulator) | ✅ pass |
| ఫోటో upload (vendor shop photos, item photos, staff live photos, offer photos) | [RUN] functions vendor-photos, shop-photo-required, photo-check tests + storage rules tests (emulator); premium_offers_test, quick_add_test (client) | ✅ pass. నిజమైన camera/gallery నుంచి upload ను phone లో చూడలేదు (phone లేదు). |
| Push notifications (price drop, offers, order status, offer alerts) | [RUN] functions notifications-domain, notifications-geo, order-notification, offer-alerts tests; push_center_test | ✅ pass. నిజమైన phone కి notification రావడం చూడలేదు (FCM, phone అవసరం). ⚠️ Server push ఇంకా పాత ఊరు/radius నియమంతో (11 Nov మార్పు server కి చేయలేదు). |
| ఏరియా/లొకేషన్ శోధన (GPS, list, pincode, place name, pin) | [RUN] area_location_test, places_test, place_resolution_test + browser run 1.8 | ✅ pass |

### 1.11 ఆఫ్ చేసినా / ఖాళీగా వదిలినా / తొలగించినా [RUN] (test/night_check/empty_and_off_test.dart)
వెబ్‌సైట్, Android app రెండింటిలో, లొకేషన్ ఉన్నప్పుడు, లేనప్పుడు:
- మొత్తం database ఖాళీ, Business Profile తొలగించారు, Business values ఖాళీ, number fields లో text (`radiusKm: 'abc'`), తప్పు theme colour, Area names లో విరిగిన rows → **20/20 crash లేదు** (km default 10 కి వెళ్తుంది).
- Scrolling Text `active=false` → దాగుతుంది ✅. Today's Offers banner `visible=false` → దాగుతుంది ✅.

### 1.12 Field పేర్ల సరిపోలిక [RUN script + CODE]
- Admin రాసే settings record ids (business, theme, scrollingText, adsConfig, rightAdBoxes, freshStrip, animations, androidHome, androidSizes, cityCodes, areaNames, inactiveAccounts, section_*) అన్నింటినీ apps అదే id తో చదువుతున్నాయి. **తేడా లేదు.**
- Admin form fields round-trip (1.4) లో 139 fields సరైన పేరుతో save అయ్యాయి. Customer వైపు (1.5) అదే పేర్లతో చదివి చూపిస్తోంది.
- Server (functions) చదివే business fields (`priceDropAutoEnabled`, `offerNotificationsEnabled`, `orderStatusNotificationsEnabled`, `autoPublishVendorChanges`, `productImageLibraryEnforced`, `deliveryFeeTiers`, `fieldPhotoLimit`...) admin అదే పేర్లతో రాస్తుంది. [CODE]

### 1.13 App లో ఉండి admin నుంచి మార్చలేనివి [CODE]
- Hero banner లోని "A LITTLE CLOSER TO HOME", "Shop the collection" (lib/ui/home_hero_slide.dart): code లోనే fix. **Translate కూడా కావు** (`.tr()` లేదు).
- Product card లోని "EVERYDAY PICK" / "LOCAL EXPERT" (home_product_tile.dart): fix (translate అవుతాయి).
- ఖాళీ Right Side Ad Box లోని "ఇక్కడ మీ ప్రకటన" (lib/domain/right_boxes.dart `rightBoxPlaceholder`): ఎప్పుడూ తెలుగులోనే.
- Tagline default "Local Shops • Local People • Better Prices": admin మార్చవచ్చు (Business Profile tagline). కానీ Android app లో tagline, header contact అసలు కనిపించవు.
- First-open sign-in sheet texts ("Welcome to LOCAMARKET"), Local Services, Nearby shops headings: code లో fix (translate అవుతాయి).
- Service boxes (Transport, Services, Shop Offers): modules నుంచి వస్తాయి, admin మార్చలేడు (రంగులు/పేర్లు fix).

### 1.14 Admin panel, vendor, staff apps నిజంగా
- **Admin panel web [RUN]** (emulator build, headless Chrome, admin path): "Business studio" login page తెరుచుకుంది: email, password, Sign in, Forgot password, "A verification code will be emailed" ✅ (shot-5). లోపలికి sign in చేసి చూడలేదు: OTP email కోసం functions emulator + mail server కావాలి. లోపలి screens ని widget tests తో నడిపాను (1.4, 1.9).
- **Vendor app, staff app [RUN via tests]**: vendor_home_test, vendor_test, vendor_items_test, vendor_ads_test, vendor_registration_gps_test, shop_ads_test, premium_offers_test, offers_module_test, plans_module_test, payments_module_test; staff_registration_test, staff_add_test, staff_areas_test, staff_auto_area_test, staff_report_test, staff_review_test, field_assistant_test, field_gps_test, quick_add_test: అన్నీ 942-suite లో pass. Browser/phone లో sign in చేసి నడపలేదు (Google / email code కి నిజమైన account, functions emulator కావాలి).

### 1.15 Builds [RUN]
- Customer website (production config): ✅ 138 s, 71 MB. Website (emulator config): ✅.
- Android release AAB: customer ✅ 72.1 MB, vendor ✅ 68.5 MB, staff ✅ 64.7 MB (`build/app/outputs/bundle/*Release/`). Version మార్చలేదు (pubspec 1.0.7+11), Desktop కి copy చేయలేదు, upload చేయలేదు. Compile check మాత్రమే.

---

# చివరి రిపోర్ట్

## A. మొత్తం స్థితి
App మొత్తం మీద పనిచేస్తోంది: admin forms లోని 139 fields సరిగ్గా save అయి website, app కి చేరుతున్నాయి. Rules (74 checks), server tests (326) అన్నీ pass. మూడు apps, website build అవుతున్నాయి. సమస్యలు: ఎక్కడా చదవని 2 fields, పాత ad rail కోసం మిగిలిన 5 fields, demo లో crash అయ్యే "Item photos" section, కొన్ని చిన్న wording/UX లోపాలు.

## B. ఆప్షన్ల పట్టిక
| ఆప్షన్ | Admin లో పనిచేస్తుందా | Website | యూజర్ app | Vendor/Staff app | ధృవీకరణ | సమస్య |
|---|---|---|---|---|---|---|
| Business Profile: km (radiusKm) | ✅ | ✅ | ✅ | paid plans కి సొంత km | RUN | - |
| Business Profile: name, tagline | ✅ | ✅ | ❌ tagline లేదు | - | RUN | Android header లో tagline లేదు |
| Business Profile: headerContact | ✅ | ✅ | ❌ | - | RUN | Android లో లేదు |
| Business Profile: noOffersMessage | ✅ | ✅ | ✅ | - | RUN | - |
| Business Profile: supportEmail, websiteUrl, vendorSignupUrl, whatsapp, phone, address | ✅ | ✅ | ✅ | ✅ | RUN save / CODE read | - |
| Business Profile: serviceTowns | ✅ | ✅ picker | ✅ | - | RUN save / CODE | - |
| Business Profile: enabledLanguages | ✅ | ✅ | ✅ | - | RUN save / CODE | - |
| Business Profile: deliveryFeeTiers, freeDeliveryAbove | ✅ | ✅ cart | ✅ cart | server placeOrder | RUN | - |
| Business Profile: payment options | ✅ | ✅ cart | ✅ cart | server | RUN save / CODE | - |
| Business Profile: **directVendorPaymentInstructions** | ✅ save | ❌ | ❌ | ❌ | RUN save + CODE | **ఎక్కడా చదవరు** |
| Business Profile: vendorPhotoLimit, fieldPhotoLimit, quickItemsPerDay* | ✅ | - | - | ✅ | RUN save + server tests | - |
| Business Profile: autoPublish, priceDropAuto, productImageLibraryEnforced, exclusiveExpiryNoticeDays | ✅ | server | server | ✅ | RUN save + server tests | - |
| Business Profile: storageWarningGb | ✅ | - | - | - | CODE (admin Insights మాత్రమే) | - |
| Theme (22 fields) | ✅ | ✅ | ✅ | - | RUN save / CODE read | - |
| Animations | ✅ | ✅ | ✅ | - | RUN (existing tests) | - |
| Scrolling Text (text, colours, speed, translations, notices) | ✅ | ✅ | ✅ | - | RUN | - |
| Scrolling Text: **noticeType** | ✅ save | ❌ | ❌ | - | RUN save + CODE | **ఎక్కడా చదవరు** |
| Scrolling Text active=false | ✅ | ✅ దాగుతుంది | ✅ | - | RUN | - |
| Today's Offers banner (ఏరియా title, visible) | ✅ | ✅ | ✅ | - | RUN browser + tests | admin text title కి వాడరు (మీ నిర్ణయం) |
| Today's Offers Box (carousel promotions) | ✅ shop తప్పనిసరి | ✅ | ✅ | - | RUN | ఇప్పుడున్న 14 offers కి shop లేదు |
| Promotions: width, spacing, position, scrollEnabled, stopAfter | ✅ save | ❌ | ❌ | - | RUN save + CODE | **పాత ad rail కోసం, అది page లో లేదు** |
| Fresh Fruits & Vegetables | ✅ | ✅ | ✅ | - | RUN (existing tests) | km లోపు products మాత్రమే |
| Right Side Ads (ads, adsConfig) | ✅ customer ads కి shop తప్పనిసరి | ✅ | ✅ strip | vendor/staff bottom box ✅ | RUN | - |
| Right Side Ad Boxes | ✅ | ✅ | ✅ | - | RUN | ఖాళీ box text ఎప్పుడూ తెలుగు |
| Layout / Visual Editor / Page view | ✅ | ✅ | ✅ (Android sizes వేరు) | - | RUN (existing tests) | - |
| Android App (androidHome, androidSizes) | ✅ | వెబ్ పట్టించుకోదు ✅ | ✅ | - | RUN | - |
| Area names | ✅ | ✅ | ✅ | - | RUN | - |
| City codes | ✅ | - | - | ✅ vendor IDs | RUN | - |
| Categories, Services, Products, Shops, Locations, Image Library | ✅ (round-trip) | ✅ | ✅ | ✅ | RUN | category తప్పనిసరి |
| Shops without location | ✅ | km లెక్కకు ముఖ్యం | ✅ | - | RUN (screen opens) | - |
| Field Assistants approve/suspend | ✅ | - | - | ✅ staff | RUN (tests + server) | - |
| Item photos (module) | ❌ demo లో crash | ✅ | ✅ | ✅ | RUN | Firebase check లేదు (live లో OK) |
| Transport (module) | ✅ | ✅ | ✅ | ✅ | RUN | - |
| Plans, Vendor Offers, Premium, Payments, Flash, Staff Areas | ✅ తెరుచుకుంటాయి | ✅ | ✅ | ✅ | RUN (module + server tests) | - |
| Inactive accounts, Push centre | ✅ | server | server | - | RUN (tests + server) | - |
| Login (Google / email code), logout, role switch | - | ✅ | ✅ | ✅ | RUN tests + server; admin login page browser | నిజమైన Google account తో చూడలేదు |
| ఫోటో upload | - | ✅ | ✅ | ✅ | RUN (server + storage rules + client tests) | phone camera తో చూడలేదు |
| Notifications | ✅ switches | server | server | server | RUN server tests | server ఇంకా ఊరు/radius నియమం |
| ఏరియా శోధన, first-open permission | - | ✅ | ✅ (tests) | - | RUN browser (4 పరిస్థితులు) + tests | ఏరియా పేరు OSM పై (Boyapalem) |
| Roles / Firestore + Storage rules | - | - | - | - | RUN 74 + 326 | storage.rules warning (హాని లేదు) |

## C. పని చేయని / సమస్య ఉన్నవి (తీవ్రత క్రమంలో)
**మధ్యస్థం**
1. **Shop లేని 14 admin offers** (production database): deploy తర్వాత ఎవరికీ కనిపించవు. పరిష్కారం: Admin → Promotions లో ప్రతి offer కి shop ఎంచుకోవాలి (డేటా, code కాదు).
2. **ఏరియా పేరు OSM పై ఆధారం** (lib/services/area_lookup.dart): Kancharapalem post office GPS వద్ద "Boyapalem" వచ్చింది. పరిష్కారం: Admin → Area names లో సరిచేయడం, లేదా దగ్గరి సొంత-GPS post office ను OSM కంటే ముందు పెట్టడం పరిశీలించడం.
3. **Server push notifications పాత ఊరు/radius నియమం** (functions/notifications.js, functions/modules/offer-alerts): customer చూసే km నియమానికి సరిపోదు. పరిష్కారం: server లో కూడా shop దూరం + admin km.

**తక్కువ**
4. `settings/business.directVendorPaymentInstructions` (lib/ui/admin_fields.dart): ఎక్కడా చదవరు. పరిష్కారం: checkout లో direct payment ఎంచుకున్నప్పుడు చూపడం, లేదా field తీసేయడం.
5. `settings/scrollingText.noticeType` (lib/ui/admin_fields.dart): ఎక్కడా చదవరు. పరిష్కారం: తీసేయడం.
6. Promotions `width`, `spacing`, `position`, `scrollEnabled`, `stopAfter`: పాత ad rail (home_ad_rail.dart, home_scheduled_promo.dart) కోసం మాత్రమే. పరిష్కారం: form నుంచి తీసేయడం.
7. "Item photos" admin section (lib/modules/photolimits/admin_item_photos.dart): Firebase లేని demo లో `No Firebase App` crash. పరిష్కారం: `AdminNeedsFirebase` తో చుట్టడం.
8. Android app లో tagline, headerContact కనిపించవు (lib/ui/android_home_header.dart). పరిష్కారం: కావాలంటే menu లో చూపడం.
9. మొదటిసారి రెండు popups ఒకేసారి (first_open_sign_in.dart + storefront.dart location): GPS నిరాకరిస్తే sign-in sheet, picker రెండూ. పరిష్కారం: sign-in sheet మూసాక picker.
10. Translate కాని / fix texts: "A LITTLE CLOSER TO HOME", "Shop the collection" (lib/ui/home_hero_slide.dart, `.tr()` లేదు), ఖాళీ ad box "ఇక్కడ మీ ప్రకటన" (lib/domain/right_boxes.dart) ఎప్పుడూ తెలుగు.
11. దగ్గర్లో products లేనప్పుడు "No matching products. Try another search." (search చేయకపోయినా), Nearby shops లో పాత "change your pincode without enabling GPS" వాక్యం.
12. storage.rules line 6: role లేని login కి "Property role is undefined" warning (fail-closed). పరిష్కారం: role ఉందో ముందు చూడటం.
13. వాడని files: home_ad_rail.dart, home_scheduled_promo.dart, offers_ads_page.dart, home_categories_section.dart, home_category_tile.dart, category_images.dart, home_quick_category_nav.dart, home_shop_tile.dart, home_widgets.dart, premiumadmin_module.dart; వాడని helpers: promotionsForTown, promotionReaches, coveringCustomer, LocationTargetField, GeoTargetPicker, Store.completePlace, Store.productTown. పరిష్కారం: వాటి tests తో పాటు తీసేయడం.

## D. Fail అయిన tests కారణాలు
ఈ రాత్రి ఏ test fail కాలేదు. మీరు చెప్పిన "3 tests fail" నిన్న area/km పని చివర్లో వచ్చినవి. వాటిని పని ముగించే ముందే సరిచేశాను (అప్పుడు 942/942):
1. `test/area_location_test.dart` ("nothing before the place is known"): demo (Firebase లేనిది) లో లొకేషన్ లేకపోతే అంతా చూపించే నియమం (`Store.showsEverything`) జోడించాక, test పాత ఆశతో ఉంది. Test ని "demo అంతా చూపుతుంది, live ఏమీ చూపదు" గా మార్చాను.
2. `test/item_shops_test.dart` (బ్రాకెట్ లో ఊరి పేరు): రెండో లొకేషన్ కి GPS point లేదు, ఊరి పేరు మాత్రమే, కాబట్టి demo నియమం వల్ల అంతా కనిపించింది. Test కి Tuni GPS point ఇచ్చాను.
3. `test/premium_home_test.dart` ("with no location, none"): paid vendor boxes fallback `nearby()` వాడింది. Demo లో లొకేషన్ లేకపోతే అది అన్ని shops ఇస్తుంది. Code fix: lib/ui/home_today_offers.dart లో కఠిన `shopsInReach()` కి మార్చాను (నిన్నటి పని).


ఈ రాత్రి చివరి full run: `flutter test` → **961/961 pass** (పాత 942 + night 19). `flutter analyze lib test` → **0 errors, 0 warnings**, 18 info (పాత style infos: curly braces, deprecated speech options). Functions + rules: 326/326. Night rules: 74/74.

## E. ఇంకా చేయాల్సినవి
ఈ రాత్రి అడిగిన తనిఖీలు అన్నీ పూర్తయ్యాయి (జాబితా 0.1–0.5 లోని ప్రతి భాగం 1.1–1.15 లో కవర్ అయింది). నేను నిజంగా నడపలేకపోయినవి, వాటి కారణాలు:
1. **Admin panel లోపలికి browser లో sign in:** password + email OTP కి functions emulator, mail server కావాలి. లోపలి screens ని widget tests తో నడిపాను. చేయడానికి: functions emulator లో `ADMIN_OTP` ని test mode లో నడిపే setup.
2. **Vendor, staff apps ని నిజమైన Google/email login తో నడపడం:** test account, functions emulator (enterRole, email code) కావాలి. Widget + server tests తో చూశాను.
3. **నిజమైన phone లో:** camera/gallery ఫోటో upload, push notification రావడం, Android GPS permission dialog. Phone కావాలి (ఈ కంప్యూటర్ కి Android device కనెక్ట్ కాలేదు).
4. **Production data తో:** production database ని తాకలేదు (నియమం ప్రకారం). Shop లేని 14 offers సమస్య (C-1) production data నుంచే తెలిసింది (నిన్న చదివినది).

మీ నిర్ణయం కావాల్సినవి (code మార్పులు, ఈ రాత్రి చేయలేదు): C లోని 1–13 పరిష్కారాలలో ఏవి చేయాలి. ముఖ్యంగా C-3 (server push కి km నియమం), C-2 (ఏరియా పేరు క్రమం).

## ఈ రాత్రి మార్చిన / జోడించిన files
- కొత్తవి: `NIGHT_CHECK_REPORT.md`, `test/night_check/` (admin_form_roundtrip_test.dart, admin_to_customer_test.dart, screens_open_test.dart, empty_and_off_test.dart, rules_night.test.cjs).
- అసలు app code (lib/, functions/, rules): **ఏదీ మార్చలేదు.** Commit, deploy చేయలేదు.
- Build outputs: `build/web` కాదు, session temp లో web builds; `build/app/outputs/bundle/*Release/*.aab` (compile check) కొత్తగా తయారయ్యాయి.
- Scripts, screenshots, logs: session temp folder `night/` (cdp.mjs, seed.cjs, spa_server.py, xref.py, shot-1..5).
