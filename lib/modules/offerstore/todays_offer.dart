import 'package:cloud_firestore/cloud_firestore.dart';

/// One Today's Offers box of a paid vendor (a `vendorTodaysOffers` document, id `<vendor>_<box>`). Offers of the older kind used the
/// vendor's id as the document id and had no box or item.
class TodaysOffer {
  const TodaysOffer({
    required this.vendorId,
    required this.shopId,
    required this.photoUrl,
    required this.price,
    required this.submittedAt,
    required this.endsAt,
    this.id = '',
    this.slot = 1,
    this.productId = '',
    this.name = '',
    this.days = 0,
  });

  factory TodaysOffer.fromData(String id, Map<String, dynamic> data) => TodaysOffer(
    id: id,
    vendorId: data['vendorId']?.toString() ?? id,
    shopId: data['shopId']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    endsAt: (data['endsAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    slot: (data['slot'] as num?)?.toInt() ?? 1,
    productId: data['productId']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    days: (data['days'] as num?)?.toInt() ?? 0,
  );

  final String id, vendorId, shopId, photoUrl, productId, name;
  final num price;
  final DateTime submittedAt, endsAt;
  // Which of the vendor's boxes (1 to the plan's number) and for how many days the vendor chose.
  final int slot, days;

  bool liveAt(DateTime now) => endsAt.isAfter(now);
}
