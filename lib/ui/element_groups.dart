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
    this.label, {
    this.collection,
    this.keyPrefix,
    this.filter,
    this.staticKeys,
  }) : assert(
         (collection != null && keyPrefix != null) != (staticKeys != null),
         'a group is either Firestore-collection-backed (collection+keyPrefix) or a fixed static list (staticKeys), never both/neither',
       );
  final int mainNumber;
  final String key; // the shared template's layoutComponents key
  final String label;
  // Firestore collection the items live in, and the prefix for the
  // synthetic per-item key, e.g. 'promo-<id>' (ads/boxes/carousel slides
  // already used this exact prefix before numbering existed, from the
  // Visual Editor's per-ad resize support) -- for a dynamic,
  // admin-growable group.
  final String? collection;
  final String? keyPrefix;
  final bool Function(Entry)? filter;
  // For a FIXED group that is never added to or reordered (footer badges
  // are always exactly 6) -- each entry is already its own real
  // layoutComponents key (e.g. 'footerBadge3'), not a synthetic
  // 'prefix-id', so it keeps using the normal settings/section_<key> save
  // path untouched; this list only supplies the sub-number ordering for
  // display/navigation.
  final List<String>? staticKeys;

  bool get isStatic => staticKeys != null;

  List<Entry> members(Store store) {
    final all = store.entries(collection!);
    return filter == null ? all : all.where(filter!).toList();
  }
}

final elementGroups = <ElementGroup>[
  ElementGroup(
    15,
    'promo',
    'Offers banner carousel',
    collection: 'promotions',
    keyPrefix: 'promo',
    filter: (e) => e.text('placement') == 'carousel',
  ),
  ElementGroup(
    16,
    'categories',
    'Categories',
    collection: 'categories',
    keyPrefix: 'category',
  ),
  ElementGroup(
    23,
    'ads',
    'Advertisement boxes',
    collection: 'promotions',
    keyPrefix: 'promo',
    filter: (e) => e.text('placement') == 'ad',
  ),
  ElementGroup(
    24,
    'boxes',
    'Promotional boxes',
    collection: 'promotions',
    keyPrefix: 'promo',
    filter: (e) => e.text('placement') == 'box',
  ),
  ElementGroup(
    25,
    'crossSellStrip',
    'Fresh Fruits & Vegetables strip',
    collection: 'products',
    keyPrefix: 'crossSellProduct',
    filter: (e) =>
        e.text('categoryId') == 'cat-vegetables' ||
        e.text('categoryId') == 'cat-fruits',
  ),
  const ElementGroup(
    28,
    'footerBadges',
    'Footer badges',
    staticKeys: [
      'footerBadge1', 'footerBadge2', 'footerBadge3',
      'footerBadge4', 'footerBadge5', 'footerBadge6',
    ],
  ),
];

ElementGroup? groupForMainNumber(int main) =>
    elementGroups.where((g) => g.mainNumber == main).firstOrNull;
ElementGroup? groupForKey(String key) =>
    elementGroups.where((g) => g.key == key).firstOrNull;

/// The synthetic key for group [main]'s [sub]-th item (1-based, in the
/// group's own stable `order`, or fixed position for a static group), or
/// null if [sub] is out of range -- the ONE place "16.2" turns into an
/// actual Firestore id (or, for a static group, an existing
/// layoutComponents key), shared by both the admin's "Go to number" box
/// and the live-preview number badges.
String? resolveSubKey(Store store, int main, int sub) {
  final group = groupForMainNumber(main);
  if (group == null || sub < 1) return null;
  if (group.isStatic) {
    final keys = group.staticKeys!;
    return sub > keys.length ? null : keys[sub - 1];
  }
  final members = group.members(store);
  if (sub > members.length) return null;
  return '${group.keyPrefix}-${members[sub - 1].id}';
}

/// The reverse lookup: given a key, which group main number and 1-based
/// sub-number is it -- used to show "16.2" (not just the raw id, or the
/// flat whole number a static group's key used to have) in a sub-item's
/// own panel title.
(int main, int sub)? subNumberForKey(Store store, String key) {
  for (final group in elementGroups) {
    if (group.isStatic) {
      final index = group.staticKeys!.indexOf(key);
      if (index != -1) return (group.mainNumber, index + 1);
      continue;
    }
    if (!key.startsWith('${group.keyPrefix}-')) continue;
    final id = key.substring(group.keyPrefix!.length + 1);
    final members = group.members(store);
    final index = members.indexWhere((e) => e.id == id);
    if (index != -1) return (group.mainNumber, index + 1);
  }
  return null;
}

/// True only for a DYNAMIC group's synthetic per-item key (`promo-id`,
/// `category-id`, `crossSellProduct-id`) -- the ones that need
/// visual_editor.dart to resolve a different collection/id to read and
/// write, via [groupCollectionForKey]/[groupSubIdForKey] below. A static
/// group's own keys (e.g. 'footerBadge3') are deliberately NOT included:
/// they're already ordinary layoutComponents keys and keep using the
/// normal `settings/section_key` path untouched -- subNumberForKey above
/// still gives them their "28.3"-style display number.
bool isGroupSubKey(String key) => elementGroups
    .where((g) => !g.isStatic)
    .any((g) => key.startsWith('${g.keyPrefix}-'));

/// The item entry a dynamic-group sub-key points at, or a blank
/// placeholder if it was deleted since the admin opened this panel.
Entry groupSubEntry(Store store, String key) {
  for (final group in elementGroups.where((g) => !g.isStatic)) {
    final prefix = '${group.keyPrefix}-';
    if (!key.startsWith(prefix)) continue;
    final id = key.substring(prefix.length);
    return store
            .entries(group.collection!)
            .where((e) => e.id == id)
            .firstOrNull ??
        Entry(id, const {});
  }
  return Entry(key, const {});
}

String groupCollectionForKey(String key) => elementGroups
    .where((g) => !g.isStatic)
    .firstWhere((g) => key.startsWith('${g.keyPrefix}-'))
    .collection!;

String groupSubIdForKey(String key) {
  final group = elementGroups
      .where((g) => !g.isStatic)
      .firstWhere((g) => key.startsWith('${g.keyPrefix}-'));
  return key.substring(group.keyPrefix!.length + 1);
}
