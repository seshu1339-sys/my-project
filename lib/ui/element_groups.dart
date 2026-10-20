import '../data/store.dart';
import '../domain/catalog.dart';

/// One repeating group on the home page that gets a main number (the
/// shared template: size, and everything that must stay identical across
/// every item) plus one sub-number per actual item (color/image/
/// brightness/text style only -- never size, per the admin's own rule).
///
/// Sub-numbers are never stored anywhere: they're always computed fresh
/// from [Store.entries] (already sorted by each entry's own `order`
/// field), so a newly added item automatically gets the next sub-number
/// and nothing already numbered ever shifts.
class ElementGroup {
  const ElementGroup(
    this.mainNumber,
    this.key,
    this.label,
    this.collection,
    this.keyPrefix, {
    this.filter,
  });
  final int mainNumber;
  final String key; // the shared template's layoutComponents key
  final String label;
  final String collection; // Firestore collection the items live in
  // Prefix for the synthetic per-item key, e.g. 'promo-<id>' (ads/boxes/
  // carousel slides already used this exact prefix before numbering
  // existed, from the Visual Editor's per-ad resize support).
  final String keyPrefix;
  final bool Function(Entry)? filter;

  List<Entry> members(Store store) => filter == null
      ? store.entries(collection)
      : store.entries(collection).where(filter!).toList();
}

final elementGroups = <ElementGroup>[
  ElementGroup(
    15,
    'promo',
    'Offers banner carousel',
    'promotions',
    'promo',
    filter: (e) => e.text('placement') == 'carousel',
  ),
  ElementGroup(16, 'categories', 'Categories', 'categories', 'category'),
  ElementGroup(
    24,
    'ads',
    'Advertisement boxes',
    'promotions',
    'promo',
    filter: (e) => e.text('placement') == 'ad',
  ),
  ElementGroup(
    25,
    'boxes',
    'Promotional boxes',
    'promotions',
    'promo',
    filter: (e) => e.text('placement') == 'box',
  ),
  ElementGroup(
    26,
    'crossSellStrip',
    'Fresh Fruits & Vegetables strip',
    'products',
    'crossSellProduct',
    filter: (e) =>
        e.text('categoryId') == 'cat-vegetables' ||
        e.text('categoryId') == 'cat-fruits',
  ),
];

ElementGroup? groupForMainNumber(int main) =>
    elementGroups.where((g) => g.mainNumber == main).firstOrNull;
ElementGroup? groupForKey(String key) =>
    elementGroups.where((g) => g.key == key).firstOrNull;

/// The synthetic key for group [main]'s [sub]-th item (1-based, in the
/// group's own stable `order`), or null if [sub] is out of range -- the
/// ONE place "16.2" turns into an actual Firestore id, shared by both the
/// admin's "Go to number" box and the live-preview number badges.
String? resolveSubKey(Store store, int main, int sub) {
  final group = groupForMainNumber(main);
  if (group == null || sub < 1) return null;
  final members = group.members(store);
  if (sub > members.length) return null;
  return '${group.keyPrefix}-${members[sub - 1].id}';
}

/// The reverse lookup: given a synthetic per-item key, which group main
/// number and 1-based sub-number is it -- used to show "16.2" (not just
/// the raw Firestore id) in a sub-item's own panel title.
(int main, int sub)? subNumberForKey(Store store, String key) {
  for (final group in elementGroups) {
    if (!key.startsWith('${group.keyPrefix}-')) continue;
    final id = key.substring(group.keyPrefix.length + 1);
    final members = group.members(store);
    final index = members.indexWhere((e) => e.id == id);
    if (index != -1) return (group.mainNumber, index + 1);
  }
  return null;
}

bool isGroupSubKey(String key) =>
    elementGroups.any((g) => key.startsWith('${g.keyPrefix}-'));

/// The item entry a sub-key points at, or a blank placeholder if it was
/// deleted since the admin opened this panel.
Entry groupSubEntry(Store store, String key) {
  for (final group in elementGroups) {
    final prefix = '${group.keyPrefix}-';
    if (!key.startsWith(prefix)) continue;
    final id = key.substring(prefix.length);
    return store
            .entries(group.collection)
            .where((e) => e.id == id)
            .firstOrNull ??
        Entry(id, const {});
  }
  return Entry(key, const {});
}

String groupCollectionForKey(String key) => elementGroups
    .firstWhere((g) => key.startsWith('${g.keyPrefix}-'))
    .collection;

String groupSubIdForKey(String key) {
  final group = elementGroups.firstWhere(
    (g) => key.startsWith('${g.keyPrefix}-'),
  );
  return key.substring(group.keyPrefix.length + 1);
}
