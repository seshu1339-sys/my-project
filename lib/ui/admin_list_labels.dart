import '../domain/catalog.dart';
import '../domain/places.dart';
import '../domain/towns.dart';

/// Where a promotion shows, in words for the admin's list: "All towns", or the
/// towns/districts/states it was made for ("Rajahmundry (East Godavari), All of
/// Telangana").
String promotionLocationLabel(Entry promotion) {
  final tokens = parseLocationList(promotion.text('locations'));
  if (tokens.isEmpty) return 'All towns';
  return tokens.map(describeLocationToken).join(', ');
}

/// Whether a promotion is showing now, from its dates and Published switch:
/// "Live", "Hidden", "Expired" or "Scheduled", so an admin sees at a glance why a
/// promotion is not on the site.
String promotionStatusLabel(Entry promotion, {DateTime? now}) {
  final at = now ?? DateTime.now();
  if (!promotion.active) return 'Hidden';
  final end = DateTime.tryParse(promotion.text('endsAt'));
  if (end != null && !at.isBefore(end)) return 'Expired';
  final start = DateTime.tryParse(promotion.text('startsAt'));
  if (start != null && at.isBefore(start)) return 'Scheduled';
  return 'Live';
}

/// What is missing on a product or service that should have it, for the admin's
/// list ("No photo", "No category", "No shop", "Out of stock", "Price is 0").
/// Empty when the record is complete.
List<String> productProblems(Entry product, {Set<String>? categoryIds, Set<String>? shopIds}) => [
  if (product.text('imageUrl').isEmpty) 'No photo',
  if (product.text('categoryId').isEmpty ||
      (categoryIds != null && !categoryIds.contains(product.text('categoryId'))))
    'No category',
  if (product.text('kind') != 'service' &&
      (product.text('shopId').isEmpty ||
          (shopIds != null && !shopIds.contains(product.text('shopId')))))
    'No shop',
  if (product.number('price') <= 0) 'Price is 0',
  if (product.number('stock') <= 0) 'Out of stock',
];

/// What a promotion does when tapped, in words ("Category: Personal care", "Shop: Local Bakery", "Services page"), so two
/// promotions with the same headline can be told apart in the admin's list.
String promotionTargetLabel(
  Entry promotion, {
  required Map<String, String> categories,
  required Map<String, String> products,
  required Map<String, String> shops,
}) {
  final target = promotion.text('target').trim();
  if (target.isEmpty) return 'No click action';
  if (target == 'shops') return 'Shops page';
  if (target == 'services') return 'Services page';
  String named(String prefix, String label, Map<String, String> names) {
    final id = target.substring(prefix.length);
    return '$label: ${names[id] ?? id}';
  }

  if (target.startsWith('category:')) return named('category:', 'Category', categories);
  if (target.startsWith('product:')) return named('product:', 'Product', products);
  if (target.startsWith('shop:')) return named('shop:', 'Shop', shops);
  if (target.startsWith('http')) return 'Link';
  return target;
}

/// Where a promotion is placed on the page, in words.
String promotionPlacementLabel(Entry promotion) => switch (promotion.text('placement', 'carousel')) {
  'ad' => 'Advertisement',
  'box' => 'Promotional box',
  'ticker' => 'Ticker',
  _ => 'Banner',
};

/// Records in the order the site shows them: by their order number, then by name (so equal numbers stay in a steady order).
List<Entry> sortedByOrder(Iterable<Entry> entries) {
  final list = [...entries];
  list.sort((a, b) {
    final byOrder = a.number('order').compareTo(b.number('order'));
    if (byOrder != 0) return byOrder;
    final byName = a.text('name').toLowerCase().compareTo(b.text('name').toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return list;
}

/// True when two records share an order number, or any is not 1..n: the list can be tidied with "Renumber".
bool hasUntidyOrder(List<Entry> sorted) {
  for (final (i, e) in sorted.indexed) {
    if (e.number('order') != i + 1) return true;
  }
  return false;
}

/// The writes that give [sorted] the order numbers 1..n: only the records whose number is not already right.
Map<String, Map<String, dynamic>> renumberChanges(List<Entry> sorted) => {
  for (final (i, e) in sorted.indexed)
    if (e.number('order') != i + 1) e.id: {'order': i + 1},
};

/// [sorted] after moving the record at [oldIndex] to [newIndex] (Flutter's reorder convention), as the writes that number it 1..n.
Map<String, Map<String, dynamic>> reorderChanges(List<Entry> sorted, int oldIndex, int newIndex) {
  final moved = [...sorted];
  final item = moved.removeAt(oldIndex);
  moved.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
  return {
    for (final (i, e) in moved.indexed)
      if (e.number('order') != i + 1) e.id: {'order': i + 1},
  };
}
