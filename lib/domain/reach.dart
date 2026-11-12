import 'catalog.dart';

// ---------------------------------------------------------------------------------------------
// What a customer sees is decided by DISTANCE ONLY (owner, 11 Nov 2026): the shops, products, services, offers and ads of the shops
// within ONE number of km of the customer's place (GPS or chosen by hand), measured to each shop's saved location. The number is the
// admin's Settings > Business Profile "Customers see shops, offers and products within (km)" (settings/business.radiusKm).
//
// Town names, district / state offers, pincodes, an item's own radius or target area and a shop's own radius no longer decide
// anything, and nothing is "for everyone": an offer or ad that is not linked to a shop is shown to nobody. Only the paid vendors'
// boxes keep the km of their plan (lib/modules/showcase). Staff areas only split the staff's work; they never limit what customers see.
// ---------------------------------------------------------------------------------------------

/// The km when the admin has not set one.
const defaultReachKm = 10.0;

/// The admin's km, kept between half a km and 500 km.
double reachKmOf(Entry business) {
  final km = business.number('radiusKm', defaultReachKm);
  return km > 0 ? km.clamp(0.5, 500).toDouble() : defaultReachKm;
}

/// The shop an offer, ad, product or service belongs to: its own shop, the shop its old radius was drawn around, or the shop it opens.
/// '' when it is not linked to any shop.
String linkedShopId(Entry item) {
  for (final key in const ['shopId', 'radiusShopId']) {
    final id = item.text(key).trim();
    if (id.isNotEmpty) return id;
  }
  if (item.text('tapAction') == 'shop' && item.text('tapValue').trim().isNotEmpty) return item.text('tapValue').trim();
  final target = item.text('target').trim();
  if (target.startsWith('shop:') && target.length > 5) return target.substring(5).trim();
  return '';
}

/// The shop's saved location, or null when it has none.
({double lat, double lng})? shopPoint(Entry? shop) {
  if (shop == null) return null;
  final lat = shop.number('latitude'), lng = shop.number('longitude');
  return lat == 0 && lng == 0 ? null : (lat: lat, lng: lng);
}

/// True when [shop] has a saved location within [km] of the customer's point. False when either place is unknown.
bool shopWithinKm(Entry? shop, double? lat, double? lng, double km) {
  final point = shopPoint(shop);
  if (point == null || lat == null || lng == null) return false;
  return distanceKm(lat, lng, point.lat, point.lng) <= km;
}

/// The ids of [shops] within [km] of the customer's point (none while the point is unknown).
Set<String> shopIdsWithin(Iterable<Entry> shops, double? lat, double? lng, double km) => {
  for (final shop in shops)
    if (shopWithinKm(shop, lat, lng, km)) shop.id,
};

/// [items] whose linked shop is one of [shopIds], each once, in their given order.
List<Entry> linkedToShops(Iterable<Entry> items, Set<String> shopIds) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (shopIds.contains(linkedShopId(item)) && seen.add(item.id)) item,
  ];
}
