import 'catalog.dart';

// A vendor's items: chosen from the admin's library (productImageLibrary: name, photo, category), sold by 1-10 kg or 1-10 pieces at
// the price the vendor sets for that quantity. A vendor has 2 items unless the admin allows more (vendors/{uid}.itemLimit); items the
// admin hid count too. The server (functions/domain.js, index.js submitVendorChange) applies the same rules.

const defaultVendorItemLimit = 2;
const vendorItemQuantities = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/// Library items with no category are listed under this id.
const uncategorizedLibraryItems = '';

/// How many items the vendor may have, leaving plans aside (the admin's own number for this vendor, else 2).
int vendorItemLimit(Map<String, dynamic>? vendor) {
  final limit = vendor?['itemLimit'];
  return limit is int && limit >= 0 && limit <= 100 ? limit : defaultVendorItemLimit;
}

int? _itemCount(Object? v) => v is num && v == v.roundToDouble() && v >= 0 && v <= 100 ? v.toInt() : null;

/// How many items the vendor may add now, the same rule as the server (functions/plan-gate.js vendorItemLimitNow): the free number
/// (this vendor's own number, else the admin's free number in planServiceGates/main, else 2), or the running plan's number
/// (vendorPlanStatus: [planEndsAt] after [now], [planItemLimit], else 10) when that is bigger.
int vendorItemLimitNow(Map<String, dynamic>? vendor, {Map<String, dynamic>? planGates, DateTime? planEndsAt, Object? planItemLimit, required DateTime now}) {
  final free = _itemCount(vendor?['itemLimit']) ?? _itemCount(planGates?['freeItemLimit']) ?? defaultVendorItemLimit;
  final running = planEndsAt != null && planEndsAt.isAfter(now);
  if (!running) return free;
  final plan = _itemCount(planItemLimit) ?? 0;
  final n = plan == 0 ? 10 : plan;
  return n > free ? n : free;
}

/// "2 kg", "1 pc", "5 pcs".
String vendorItemUnit(String unitType, int quantity) => unitType == 'kg' ? '$quantity kg' : '$quantity ${quantity == 1 ? 'pc' : 'pcs'}';

/// The library items the admin switched on, in a category ([uncategorizedLibraryItems] for the ones without one), in the admin's order.
List<Entry> libraryItemsIn(List<Entry> library, String categoryId) => [
  for (final item in library)
    if (item.active && item.text('categoryId') == categoryId) item,
];

/// The categories that have at least one library item, in the admin's category order, then "Other" for items without a category.
List<(String, String)> libraryCategories(List<Entry> library, List<Entry> categories) {
  final used = {for (final item in library) if (item.active) item.text('categoryId')};
  return [
    for (final category in categories)
      if (used.contains(category.id)) (category.id, category.text('name', category.id)),
    if (used.contains(uncategorizedLibraryItems)) (uncategorizedLibraryItems, 'Other items'),
  ];
}

/// A vendor's price lasts the admin's post duration (lib/domain/post_duration.dart), 24 hours unless the admin changes it; then it is
/// removed (functions/vendor-prices.js) and the vendor enters a new one. The price's own priceExpiresAt says when.
const vendorPriceValidHours = 24;

/// Whether a vendor item's price has run out at [now]: it has no price any more, or its 24 hours are over (priceExpiresAt).
bool vendorPriceExpired(Map<String, dynamic> item, DateTime now) {
  if (item['price'] is! num) return true;
  final expires = DateTime.tryParse('${item['priceExpiresAt'] ?? ''}');
  return expires != null && !now.isBefore(expires);
}

/// The price as the vendor sees it: "₹50 for 2 kg • valid for 23 h 10 min", or "Price expired: enter a new price".
String vendorPriceLine(Map<String, dynamic> item, DateTime now) {
  if (vendorPriceExpired(item, now)) return 'Price expired: enter a new price';
  final unit = '${item['unit'] ?? ''}';
  final price = '₹${item['price']}${unit.isEmpty ? '' : ' for $unit'}';
  final expires = DateTime.tryParse('${item['priceExpiresAt'] ?? ''}');
  if (expires == null) return price;
  final left = expires.difference(now);
  if (left.inDays >= 1) return '$price • valid for ${left.inDays} d ${left.inHours % 24} h';
  return '$price • valid for ${left.inHours} h ${left.inMinutes % 60} min';
}
