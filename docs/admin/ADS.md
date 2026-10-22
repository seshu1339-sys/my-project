# Unified Ads system

One system for every ad on the customer home page (right-hand column on a wide screen, one swipeable box on a phone / the customer app),
managed in **Settings > Ads** (section number 23; each ad is a sub-number 23.1, 23.2 ...) and fed by the admin and by vendors.

## Where things are
| Part | Files |
|---|---|
| Rules (live now, size, animation, daily limit, location, tap target) | `lib/domain/ads.dart` |
| Customer boxes (column, phone pager, one box, animations) | `lib/ui/ads_column.dart`, `ad_box.dart`, `ad_transitions.dart`, `offers_ads_page.dart` |
| Counting views (device side) | `lib/services/ad_tracker.dart` |
| Counting views (server, decides what counts) | `functions/ad-tracking.js` |
| Admin: settings, list, editor, pending approvals | `lib/ui/admin_ads.dart`, `lib/domain/ads_admin.dart` |
| Admin / vendor reports | `lib/ui/admin_ad_reports.dart`, `lib/domain/ad_reports.dart`, `lib/services/report_export.dart` |
| Vendor app "My Ads" | `lib/ui/vendor_ads_page.dart` (opened from the vendor workspace) |
| Vendor submit / approve / reject / remove / summaries | `functions/vendor-ads.js` |

## Data
- `ads/<id>`: what customers see (public read, admin write). `adsPrivate/<id>`: shop contact, amount, paid, notes (admin only).
- `adSubmissions/<id>`: what a vendor sent, `pending` until the admin decides. `vendorNotices/<id>`: messages to the vendor.
- `adStats/<ad>` (totals), `adStatsDaily/<ad>~<day>` (per day, with `towns` and `devices` breakdowns), `adViews/<id>` (every counted view and tap with
  time, town, device). Written only by functions. The admin reads all; a vendor reads the totals of their own ads.
- `settings/adsConfig`: the settings that apply to all ads (slots, box size, corners, gap, border, shadow, animation, speed, seconds, label, test devices).

## What counts as a view
On screen for at least 1 second, page in front and app/tab active, at least half the box visible; once per device per ad per 30 minutes (server
and device both enforce it); never the owning vendor, admin, field staff, bots or listed test devices. "Unique people" are distinct devices.
"Missed" = the ad was due in a box but was not visible for a second. The "day" is the Indian day.

## Before this goes live (NOT deployed yet)
1. Firestore rules and indexes (`firebase deploy --only firestore`).
2. Functions: `trackAdEvents`, `submitVendorAd`, `decideVendorAd`, `removeVendorAd`, `setAdSummary`, `sendAdSummaries` (`firebase deploy --only functions`).
3. Hosting (customer + admin) and the vendor app build.
Until `ads` has a live ad the home page keeps its old ad boxes, so the site does not change by itself. Use "Copy current ad boxes here" in
Settings > Ads to bring the existing ad boxes in.

## Known limits
- Counter documents are single documents per ad / per day, which is fine at this size; a very busy ad would need sharded counters.
- Views on the "Offers & Ads" page are not counted (taps are); only the home boxes count views.
- A push notification only reaches a vendor who has notifications on; the message is always in the vendor app's "My Ads".
