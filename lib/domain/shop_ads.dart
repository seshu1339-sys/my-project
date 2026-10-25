import 'catalog.dart';
import 'right_boxes.dart';

// Shop ads in the Right Side Ad Boxes (functions/shop-ads.js), arranged offline for now. A vendor ticks "Ad for your shop"
// (vendors/<uid>.adInterest); the office calls them, uploads the ad photo into a box and links the box to the vendor. That starts an
// ad, rightBoxAds/<adId>:
//   box          the Right Side Ad Box number
//   vendorId     the vendor (with vendorName and vendorCode, the Vendor ID)
//   status       live | ended (a new vendor in the box, or the box unlinked, ends it)
//   startedAt    when it started; endedAt when it ended
//   payment      offline (lib/services/shop_ad_payment.dart)
// Its views are counted like every other ad's (functions/ad-tracking.js) into adStats/<adId>: the total since the ad started, which
// is what the vendor app shows (not who is watching now).

class ShopAd {
  const ShopAd({required this.id, required this.box, required this.vendorId, this.vendorName = '', this.vendorCode = '', required this.live, this.startedAt, this.endedAt});
  final String id, vendorId, vendorName, vendorCode;
  final int box;
  final bool live;
  final DateTime? startedAt, endedAt;

  factory ShopAd.from(Entry e) => ShopAd(
    id: e.id,
    box: e.number('box').round(),
    vendorId: e.text('vendorId'),
    vendorName: e.text('vendorName'),
    vendorCode: e.text('vendorCode'),
    live: e.text('status') == 'live',
    startedAt: shopAdTime(e.data['startedAt']),
    endedAt: shopAdTime(e.data['endedAt']),
  );
}

/// Only the records that really are shop ads, the live ones first, then the ended ones, the newest first in each.
List<ShopAd> shopAdsInOrder(Iterable<Entry> records) {
  final ads = [for (final e in records) if (e.id.startsWith(rightBoxAdPrefix)) ShopAd.from(e)];
  int newest(ShopAd a, ShopAd b) => (b.startedAt ?? DateTime(2000)).compareTo(a.startedAt ?? DateTime(2000));
  return [...ads.where((a) => a.live).toList()..sort(newest), ...ads.where((a) => !a.live).toList()..sort(newest)];
}

/// The total views the server counted for each ad (adStats records, by ad id).
Map<String, int> shopAdViews(Iterable<Entry> stats) => {for (final s in stats) s.id: s.number('views').round()};

/// The total taps the server counted for each ad.
Map<String, int> shopAdTaps(Iterable<Entry> stats) => {for (final s in stats) s.id: s.number('taps').round()};

/// Reads a Firestore Timestamp, DateTime, ISO string or milliseconds.
DateTime? shopAdTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  try {
    return ((value as dynamic).toDate() as DateTime).toLocal();
  } catch (_) {
    return null;
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "25 Oct 2026", or '' when there is no date yet (the server has not stamped it).
String shopAdDate(DateTime? d) => d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// A count the Indian way: 1,234 and 1,23,456.
String shopAdCount(int n) {
  final digits = '${n.abs()}';
  if (digits.length <= 3) return '${n < 0 ? '-' : ''}$digits';
  final head = digits.substring(0, digits.length - 3), tail = digits.substring(digits.length - 3);
  final groups = <String>[];
  for (var end = head.length; end > 0; end -= 2) {
    groups.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
  }
  return '${n < 0 ? '-' : ''}${groups.join(',')},$tail';
}
