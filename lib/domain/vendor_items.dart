import 'catalog.dart';

// A vendor's items: chosen from the admin's library (productImageLibrary: name, photo, category), sold by 1-10 kg or 1-10 pieces at
// the price the vendor sets for that quantity. A vendor has 2 items unless the admin allows more (vendors/{uid}.itemLimit); items the
// admin hid count too. The server (functions/domain.js, index.js submitVendorChange) applies the same rules.

const defaultVendorItemLimit = 2;
const vendorItemQuantities = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/// Library items with no category are listed under this id.
const uncategorizedLibraryItems = '';

/// How many items the vendor may have.
int vendorItemLimit(Map<String, dynamic>? vendor) {
  final limit = vendor?['itemLimit'];
  return limit is int && limit >= 0 && limit <= 100 ? limit : defaultVendorItemLimit;
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
