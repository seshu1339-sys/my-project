import 'catalog.dart';

/// The home page shows OUR catalog photo of an item, never a vendor's own model photo (owner, 16 Nov 2026): those show only on the
/// item's shop list. An item with no catalog photo (one the vendor named, not in the catalog) keeps its own.
Entry homePhoto(Entry product) {
  final catalog = product.text('libraryImageUrl');
  if (product.data['ownPhoto'] != true || catalog.isEmpty || catalog == product.text('imageUrl')) return product;
  return Entry(product.id, {...product.data, 'imageUrl': catalog});
}
