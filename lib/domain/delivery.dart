import 'catalog.dart';

/// The delivery charge of one shop in an order. This is the same rule as functions/domain.js (shopDeliveryCharge), which has the last
/// word when the order is sent; the app uses it only to show the charge beforehand. Only the admin sets any of it:
/// settings/business.deliveryFeeTiers and freeDeliveryAbove, and a shop's freeDelivery switch. The charge is paid to the vendor directly.
class DeliveryPart {
  const DeliveryPart({required this.shopId, required this.shopName, required this.fee, this.talkToVendor = false, this.distanceKm});
  final String shopId;
  final String shopName;
  final double fee;

  /// True when the distance is past the last tier (or not known): the customer settles the charge with the vendor by phone.
  final bool talkToVendor;
  final double? distanceKm;
}

class DeliveryTier {
  const DeliveryTier(this.km, this.fee);
  final double km;
  final double fee;
}

/// "5:10, 10:20, 15:0" -> up to 5 km Rs 10, up to 10 km Rs 20, up to 15 km free. Pieces that are not "km:fee" are left out.
List<DeliveryTier> parseDeliveryTiers(String text) {
  final tiers = <DeliveryTier>[];
  for (final part in text.split(',')) {
    final pieces = part.split(':');
    if (pieces.length != 2) continue;
    final km = double.tryParse(pieces[0].trim());
    final fee = double.tryParse(pieces[1].trim());
    if (km == null || fee == null || km <= 0 || fee < 0) continue;
    tiers.add(DeliveryTier(km, fee));
  }
  tiers.sort((a, b) => a.km.compareTo(b.km));
  return tiers;
}

/// One part per shop in the order. [subtotals] is shop id -> the value of that shop's items. [shops] are the shop entries.
List<DeliveryPart> buildDeliveryParts({
  required Map<String, double> subtotals,
  required Iterable<Entry> shops,
  required Entry business,
  required double? latitude,
  required double? longitude,
}) {
  final tiers = parseDeliveryTiers(business.text('deliveryFeeTiers'));
  final freeAbove = business.number('freeDeliveryAbove');
  final byId = {for (final shop in shops) shop.id: shop};
  return [
    for (final MapEntry(key: shopId, value: subtotal) in subtotals.entries)
      () {
        final shop = byId[shopId];
        final name = shop?.text('name') ?? '';
        DeliveryPart part(double fee, {bool talk = false, double? km}) => DeliveryPart(shopId: shopId, shopName: name, fee: fee, talkToVendor: talk, distanceKm: km);
        if (shop?.data['freeDelivery'] == true) return part(0);
        if (freeAbove > 0 && subtotal >= freeAbove) return part(0);
        if (tiers.isEmpty) return part(0);
        final shopLat = shop?.data['latitude'], shopLng = shop?.data['longitude'];
        if (shopLat is! num || shopLng is! num || latitude == null || longitude == null) return part(0, talk: true);
        final km = (distanceKm(latitude, longitude, shopLat.toDouble(), shopLng.toDouble()) * 10).round() / 10;
        for (final tier in tiers) {
          if (km <= tier.km) return part(tier.fee, km: km);
        }
        return part(0, talk: true, km: km);
      }(),
  ];
}
