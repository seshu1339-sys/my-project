# Responsive customization handoff

## Completed

The existing Flutter project now uses available viewport width instead of the fixed 1,050 px homepage. Mobile components stack, tablet grids use moderate columns, and desktop grids share space with the advertising rail. Product cards grow naturally for readable content. Uploaded images keep their aspect ratio without the previous low-resolution decode limit.

Administrators can open **Business admin → UI Customization / Layout Settings**. Component groups include Header, Logo, User/location, Search Box, Services, Office, Ticker, Banners, Categories, Product cards, Popular Products, Nearby shops/map, Ads, Promotional boxes and Page layout. Only applicable controls are presented. Settings persist through the existing Firestore or demo storage, with bounded values and per-component reset. Global font and color settings remain in Theme Settings; the font-family application was corrected.

Search controls are independent of Services and other components. Voice and camera remain icons using the existing provider hooks. Banners support responsive visible counts and sizing. Tickers retain translations, scheduling, both directions and pause/resume. Ads/promos retain individual content, schedule, order, dimensions and style, with independent upward scrolling and timed stopping. Office contact details are revealed on request. Services search opens existing product/provider details with Call and WhatsApp actions.

Existing Firebase initialization/configuration, backend functions/rules, price/stock/cart/checkout logic, account/order/review flows and detail routes remain in place. No production catalog records were changed during validation.

## Files changed

| Files | Change |
| --- | --- |
| `lib/ui/layout_settings.dart` (new) | Shared constraints, breakpoints and component control definitions |
| `lib/ui/layout_editor.dart` (new) | Grouped persistent settings, validation, independent reset |
| `lib/ui/responsive_header.dart` (new) | Responsive header/search, language/account/location/admin actions, office reveal and contact actions |
| `lib/ui/services_page.dart` (new) | Searchable service catalog using existing products and detail screens |
| `lib/ui/wireframe_home.dart` | Adapted the active homepage composition and removed fixed page width |
| `lib/ui/storefront.dart` | Connected existing navigation/scroll keys, service and promotion routes |
| `lib/ui/home_widgets.dart` | Adaptive category/product sizing and safe text/card layout |
| `lib/ui/home_promotions.dart` | Adjustable carousel, measured ticker speed/direction, independent ad clocks and stopping |
| `lib/ui/home_hero_slide.dart` | Applied configurable banner styling |
| `lib/ui/shared.dart` | Safe numeric parsing, visibility handling, transparent backgrounds and image quality |
| `lib/ui/admin.dart` | Layout-settings entry, per-promotion playback/position fields, office/provider fields, category image field, compact section navigation |
| `lib/ui/details.dart` | Provider/shop contact actions and configurable/clickable nearby maps |
| `lib/main.dart` | Global font family now applies to the text theme |
| `test/layout_model_test.dart` (new) | Breakpoint precedence and dimension bounds |
| `test/responsive_settings_test.dart` (new) | Settings persistence/reset/isolation, extreme sizes, banners, ticker, ads and services |
| `test/home_layout_test.dart` | Seven viewport sizes, large text, empty collections and rendered visual checks |
| `test/widget_test.dart`, `test/admin_test.dart` | Existing search/cart/admin regression checks adapted to responsive scrolling |
| `docs/home-ui.md` | Configuration and architecture guide |
| `docs/responsive-validation.md` | This handoff |

## Checks

- Flutter analysis: **no issues found**.
- Flutter tests: **33 passed**.
- Viewports: **320, 390, 768, 1024, 1440, 1920 and 2560 px**; large accessibility text and extreme stored dimensions are included.
- Visual inspection: phone/tablet/desktop/large-monitor Flutter renders, including product-grid views. Artifacts are in `build/home-*.png`.
- Search: verified a persisted desktop width of 520 and height of 100, with Services unchanged.
- Banners: verified five visible cards on desktop, reduction on mobile, and configured height.
- Ticker: verified both movement directions and pause.
- Ads: verified negative vertical movement and stopping after the configured duration.
- Existing tests: product search, cart, admin category creation, pincode pricing, radius filtering, scheduling and item-view tracking pass.
- Web build: compiled with the existing `firebase-config-web.json`. Build output is `build/web`; logs are `build/responsive-web-build.log`.

## Chrome verification follow-up — 2026-09-17

The current Firebase-configured release build now runs in installed Google Chrome at `http://localhost:8090`. The web build succeeded again. No application source changes were needed during this verification follow-up.

An isolated Playwright harness using installed Chrome overcame the earlier unavailable browser connection. Saved live results cover 12 checks: widths 390/768/1440/2560, voice/image fallback messages, typed search, Services, office contact reveal, account/cart routes and dismissible location selection. Screenshots at all four widths were visually reviewed; the live catalog currently has sparse content, which was left unchanged.

The existing demo mode is served separately on port 8091 for admin writes and populated catalog checks. Chrome confirms independent search sizing, persisted width 520 and height 100 after reload, component reset, five visible banner cards at height 180, ticker pause/resume, search-to-cart pricing (₹249), service search to provider Call/WhatsApp controls, and manual pincode persistence without GPS. A separate motion check confirms upward ad movement followed by its configured stop timer. The ad test changes only isolated demo browser storage.

All **22 browser checks passed** (12 live, 8 demo flow, 2 ad motion), with **no captured JavaScript page errors**. Browser results and screenshots are in `build/browser-check/`; `live-results.json`, `demo-results.json` and `motion-results.json` record the executed checks. This harness is temporary build tooling, not an application dependency. The live server returned HTTP 200 at the end of verification. Prior passing analysis and 33 Flutter tests were retained; source code was unchanged, so those suites were not unnecessarily repeated.

Provider setup guidance is in [search-provider-setup.md](search-provider-setup.md), tailored to the existing interfaces and Firebase project. Both recognition providers remain unconfigured.

## Remaining verification limits

Live administrator writes, SMS sign-in, real order submission and external Call/WhatsApp launching were not exercised against production. Voice/image recognition providers were already unconfigured; their hooks and explanatory UI remain intact.
