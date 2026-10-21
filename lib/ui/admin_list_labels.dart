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
