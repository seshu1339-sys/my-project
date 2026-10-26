import 'catalog.dart';
import 'item_shops.dart';

// The home page's "Fresh Fruits & Vegetables" strip: the items the admin chose, in the admin's order (settings/freshStrip
//   items: [{name, libraryItemId, productId, imageUrl}, ...], see ItemPick in item_shops.dart).
// Each item is found by name among the shops' products (the same item at many shops); the strip shows the one with the lowest price
// in the customer's town, with the item's photo. With no items chosen, the strip shows the vegetables and fruits as before.

const freshStripRecord = 'freshStrip';

/// How many items the strip shows at once; the next ones come after a while.
const freshStripPageSize = 9;

/// The admin's items, in order (none when nothing is chosen).
List<ItemPick> freshStripItems(Entry? record) => [
  for (final v in (record?.data['items'] as List? ?? const []))
    if (v is Map && '${v['name'] ?? ''}'.trim().isNotEmpty) ItemPick.from(v),
];

/// The strip's cards, in the admin's order: for each item, its product with the lowest price among [products] (the customer's
/// town), showing the item's photo when that product has none. Items no shop there sells are left out.
List<Entry> freshStripProducts(List<ItemPick> items, List<Entry> products, String pincode) {
  final out = <Entry>[];
  for (final item in items) {
    Entry? best;
    for (final p in products) {
      if (p.text('kind') == 'service' || p.price(pincode) <= 0) continue;
      if (p.id != item.productId && !isSameItem(p, name: item.name, libraryItemId: item.libraryItemId)) continue;
      if (best == null || p.price(pincode) < best.price(pincode)) best = p;
    }
    if (best == null) continue;
    out.add(best.text('imageUrl').isEmpty && item.imageUrl.isNotEmpty ? Entry(best.id, {...best.data, 'imageUrl': item.imageUrl}) : best);
  }
  return out;
}

/// [items] cut into pages of [size] (the strip shows one page at a time).
List<List<T>> pagesOf<T>(List<T> items, [int size = freshStripPageSize]) => [
  for (var i = 0; i < items.length; i += size) items.sublist(i, i + size > items.length ? items.length : i + size),
];
