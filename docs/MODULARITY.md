# Modularity: modules and sections

Four apps from one codebase: **customer** (lib/main.dart), **admin** (main_admin.dart), **vendor** (main_vendor.dart), **staff** (main_field.dart).
Check the boundaries any time: `node scripts/module-graph.cjs` (what each app can reach, who depends on whom) and
`node scripts/why-reach.cjs <entry>.dart <file>` (the import chain to a file). `test/modularity_test.dart` fails when a change breaks a rule below.

## Rules (enforced by test/modularity_test.dart)
- The vendor and staff apps carry none of the customer-site, admin, or each other's screens.
- No home section / header imports an admin, vendor, staff, Quick Add or AI screen; a home section imports the piece it uses, not a barrel.
- The vendor sections (vendor_section_*.dart) share only vendor_section_kit.dart, never each other; the admin panel does not import them.
- domain/ imports only domain/; services/ and data/ import no screens (except design tokens and ui/shared.dart, the shared kernel).
- ui/shared.dart (used by every app) does not pull in the customer layout engine.
- No import cycles, except the Store extensions and the shop page / product page pair.

## What was found and changed
| Finding | Change |
|---|---|
| ui/shared.dart imported the customer layout engine, so the vendor and staff apps carried it | The two layout-dependent helpers moved to ui/page_widgets.dart (customer pages only). Vendor 52 -> 47 files, staff 40 -> 34. |
| Vendor "My Ads" used a page in the admin file group | Reports page is neutral: ui/ad_reports_page.dart. |
| A home section (Nearby) imported the barrel of all customer pages | It imports shop_page.dart only; the admin preview no longer pulls the whole page tree through it. |
| home sections imported barrels (home_promotions, home_widgets) | They import the specific files. |
| vendor_page <-> vendor_registration_form cycle; radius <-> catalog cycle; product_search <-> details barrel cycle | Shared piece moved next to its owner; promotionReaches() lives in radius.dart. |
| **Today's Offers banner read the Scrolling Text record** (its label, border, colours, fonts) and the Today's Offers Box's heading animation | Independent once `section_notice.independent = true` (Settings > Today's Offers button, or scripts/decouple-notice.cjs). Until then the old behaviour, so the live look does not change by itself. |
| Settings > Animations and Ads settings saved the WHOLE record from an old copy, undoing what another page saved | They write only what they changed (Store.updateFields). |
| VendorWorkspace was one 400-line state with one shared busy flag and shared text boxes | Nine sections, each its own widget / state / busy flag / streams (vendor_section_*.dart). |
| quick_add.dart: 1500 lines, 25 classes | Seven parts (quick_add_core, _entry, _shop, _photo, _item, _batch, _items); quick_add.dart re-exports them. |

## Still shared on purpose
- Admin Visual Editor / Page view embed the real customer home page (WireframeHome) as a read-only preview, so the admin app reaches the customer
  home widgets. The customer home never imports the admin.
- The customer web build includes the admin route (/jyothi9) until it is removed; the customer Android build does not (scripts/check-app-isolation.cjs).
- Settings pages that edit the same record (Animations, Right Side Ads, Layout) are two views of one value; each saves only its own changes.
- ui/responsive_header_bar.dart (one 700-line build, each element reading its own layout key) is the largest remaining monolith; its elements are
  independent in settings but not yet separate widgets.

## Home modules (lib/modules/)
Transport and Services are two modules. Each has its own folder (`lib/modules/transport/`, `lib/modules/services/`), its own route name
(`/transport`, `/services`) and its own data. They do not import each other, nor Shops, Promotions, vendor, Quick Add, admin or ads files
(`test/module_independence_test.dart` fails if they do). The home page boxes under Today's Offers (`ui/home_module_boxes.dart`) and the
Settings sections of the admin panel only read the list in `lib/modules/modules.dart`: removing or changing one module is its folder plus one
line in that list; the others keep working.

| Module | Route | Data | Home box | Admin section |
|---|---|---|---|---|
| Transport | /transport | its own collection `transport` (empty; nothing stored yet) | teal box, opens a page that says "త్వరలో వస్తుంది" | Settings > Transport (empty for now) |
| Services | /services | the A-Z service types are the module's own file (assets/services/services_list.json); the service listings are still the records of kind "service" in the shared `products` collection (vendors and Quick Add create them there) | orange box, opens the Services page | (uses the existing product pages) |

Not done yet: moving the service listings into a `services` collection of their own (a data migration plus vendor and Quick Add changes).
