import 'catalog.dart';

/// Categories that ship with a built-in photo (assets/category_icons/SLUG.webp).
/// A category gets its photo when its id (`cat-electronics`) or its name
/// ("Electronics") is one of these. It is only the default: a photo the admin
/// sets on the category in Business Studio (its image URL) always wins, and
/// clearing that field brings the built-in one back.
const builtInCategorySlugs = {
  'books',
  'clothes',
  'electricals',
  'electronics',
  'fancy',
  'footwear',
  'mobiles',
  'plastics',
};

String _slug(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The bundled photo for [category], or null when it has none.
String? builtInCategoryImage(Entry category) {
  final fromId = _slug(category.id.replaceFirst(RegExp(r'^cat-'), ''));
  final fromName = _slug(category.text('name'));
  for (final slug in [fromId, fromName]) {
    if (builtInCategorySlugs.contains(slug)) {
      return 'assets/category_icons/$slug.webp';
    }
  }
  return null;
}
