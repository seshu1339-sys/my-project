import 'package:cloud_firestore/cloud_firestore.dart';

/// One vendor's offer (a `vendorTodaysOffers` document; the vendor's id is the document id).
class TodaysOffer {
  const TodaysOffer({required this.vendorId, required this.shopId, required this.photoUrl, required this.price, required this.submittedAt, required this.endsAt});

  factory TodaysOffer.fromData(String id, Map<String, dynamic> data) => TodaysOffer(
    vendorId: id,
    shopId: data['shopId']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    endsAt: (data['endsAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String vendorId, shopId, photoUrl;
  final num price;
  final DateTime submittedAt, endsAt;

  bool liveAt(DateTime now) => endsAt.isAfter(now);
}
