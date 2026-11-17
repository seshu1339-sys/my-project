import 'package:cloud_firestore/cloud_firestore.dart';

/// One offer as a vendor made it (a `vendorOffers` document).
class VendorOffer {
  const VendorOffer({
    required this.id,
    required this.vendorId,
    required this.shopId,
    required this.shopName,
    required this.title,
    required this.details,
    required this.offerPrice,
    required this.regularPrice,
    required this.photos,
    required this.status,
    required this.removedReason,
    required this.endsAt,
    this.alertRadiusKm = 0,
    this.alertOn = false,
    this.alertStatus = '',
  });

  factory VendorOffer.fromData(String id, Map<String, dynamic> data) {
    final ends = data['endsAt'];
    return VendorOffer(
      id: id,
      vendorId: data['vendorId']?.toString() ?? '',
      shopId: data['shopId']?.toString() ?? '',
      shopName: data['shopName']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      details: data['details']?.toString() ?? '',
      offerPrice: (data['offerPrice'] as num?) ?? 0,
      regularPrice: data['regularPrice'] as num?,
      photos: [for (final url in data['photos'] as List? ?? const []) url.toString()],
      status: data['status']?.toString() ?? '',
      removedReason: data['removedReason']?.toString() ?? '',
      endsAt: ends is Timestamp ? ends.toDate() : null,
      alertRadiusKm: (data['alertRadiusKm'] as num?)?.toInt() ?? 0,
      alertOn: data['alert'] == true || (data['alert'] == null && ((data['alertRadiusKm'] as num?) ?? 0) > 0),
      alertStatus: data['alertStatus']?.toString() ?? '',
    );
  }

  final String id, vendorId, shopId, shopName, title, details, status, removedReason;
  final num offerPrice;
  final num? regularPrice;
  final List<String> photos;
  final DateTime? endsAt;
  // The nearby alert: asked for or not, the km it reached (the vendor's plan km, written when it is sent; 0 before) and what happened
  // to it (functions/modules/offer-alerts).
  final bool alertOn;
  final int alertRadiusKm;
  final String alertStatus;

  bool get removed => status == 'removed';
  bool get waiting => status == 'pending';
  bool endedAt(DateTime now) => endsAt == null || !endsAt!.isAfter(now);
  bool liveAt(DateTime now) => status == 'live' && !endedAt(now);
}

/// What a customer sees: live offers of the shops given (hidden shops are not among them), the ones ending soonest first.
List<VendorOffer> offersForCustomer(List<VendorOffer> offers, Set<String> shopIds, DateTime now) =>
    [for (final offer in offers) if (offer.liveAt(now) && shopIds.contains(offer.shopId)) offer]
      ..sort((a, b) => a.endsAt!.compareTo(b.endsAt!));

String offerPriceText(num price) => price == price.roundToDouble() ? '₹${price.round()}' : '₹${price.toStringAsFixed(2)}';

String offerDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

/// The line under an offer in the vendor's own list and the admin's list.
/// The nearby alert as the vendor reads it: that it went, or why not. Never how many people got it.
String? offerAlertText(VendorOffer offer) {
  if (!offer.alertOn) return null;
  final km = offer.alertRadiusKm > 0 ? '${offer.alertRadiusKm} km' : 'your plan km';
  return switch (offer.alertStatus) {
    'sent' => 'Alert sent to customers within $km',
    'sending' => 'Sending the alert within $km...',
    'daily-limit' => 'Alert not sent: one alert a day. Your offer is live.',
    'no-shop-location' => 'Alert not sent: your shop has no map location yet. Your offer is live.',
    'disabled' => 'Alerts are paused just now. Your offer is live.',
    'paid-only' => 'Alert not sent: alerts are for Silver, Gold and Premium plans. Your offer is live.',
    _ => offer.waiting ? 'The alert within $km goes when the offer is approved' : 'Alert within $km',
  };
}

String offerStatusText(VendorOffer offer, DateTime now) {
  if (offer.removed) return 'Removed by the administrator${offer.removedReason.isEmpty ? '' : ': ${offer.removedReason}'}';
  if (offer.endedAt(now)) return 'Ended${offer.endsAt == null ? '' : ' on ${offerDate(offer.endsAt!)}'}';
  if (offer.waiting) return 'Waiting for approval, until ${offerDate(offer.endsAt!)}';
  return 'Live until ${offerDate(offer.endsAt!)}';
}
