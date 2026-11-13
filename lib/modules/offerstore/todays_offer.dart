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
    this.note = '',
    this.hidden = false,
    this.waitingCheck = false,
    this.untilPlanEnds = false,
    this.vendorCode = '',
    this.planName = '',
    this.libraryItemId = '',
    this.ownPhoto = false,
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
    note: data['note']?.toString() ?? '',
    hidden: data['hidden'] == true,
    waitingCheck: data['waitingCheck'] == true,
    untilPlanEnds: data['untilPlanEnds'] == true,
    vendorCode: data['vendorCode']?.toString() ?? '',
    planName: data['planName']?.toString() ?? '',
    libraryItemId: data['libraryItemId']?.toString() ?? '',
    ownPhoto: data['ownPhoto'] == true,
  );

  final String id, vendorId, shopId, photoUrl, productId, name;
  final num price;
  final DateTime submittedAt, endsAt;
  // Which of the vendor's boxes (1 to the plan's number) and for how many days the vendor chose.
  final int slot, days;
  // Owner, 13 Nov 2026: the vendor's short offer text; hidden by the admin (or waiting for the admin when the photo check could not run);
  // running with the plan (no days chosen); who and which plan, for the admin; a catalog item or the vendor's own photo.
  final String note, vendorCode, planName, libraryItemId;
  final bool hidden, waitingCheck, untilPlanEnds, ownPhoto;

  /// Customers see an offer until its end, unless the admin hid it.
  bool liveAt(DateTime now) => !hidden && endsAt.isAfter(now);

  /// The vendor sees their own boxes until the end, hidden ones too (marked).
  bool runningAt(DateTime now) => endsAt.isAfter(now);
}
