import 'package:cloud_firestore/cloud_firestore.dart';

/// A wholesale offer as the admin edits it (a `wholesaleOffers` document).
class AdminWholesale {
  const AdminWholesale({required this.id, required this.name, required this.photoUrl, required this.price, required this.minQuantity, required this.validUntil, required this.wholesaler, required this.phone});

  factory AdminWholesale.fromData(String id, Map<String, dynamic> data) => AdminWholesale(
    id: id,
    name: data['name']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    minQuantity: data['minQuantity']?.toString() ?? '',
    validUntil: (data['validUntil'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    wholesaler: data['wholesaler']?.toString() ?? '',
    phone: data['phone']?.toString() ?? '',
  );

  final String id, name, photoUrl, minQuantity, wholesaler, phone;
  final num price;
  final DateTime validUntil;
}

/// A vendor's Today's Offer as the admin sees it (a `vendorTodaysOffers` document). [vendorId] is the document id (the offer's id).
class AdminVendorOffer {
  const AdminVendorOffer({
    required this.vendorId,
    required this.shopId,
    required this.photoUrl,
    required this.price,
    required this.endsAt,
    this.vendorCode = '',
    this.planName = '',
    this.tier = '',
    this.name = '',
    this.note = '',
    this.hidden = false,
    this.waitingCheck = false,
    this.untilPlanEnds = false,
    this.ownPhoto = false,
  });

  factory AdminVendorOffer.fromData(String id, Map<String, dynamic> data) => AdminVendorOffer(
    vendorId: id,
    shopId: data['shopId']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    endsAt: (data['endsAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    vendorCode: data['vendorCode']?.toString() ?? '',
    planName: data['planName']?.toString() ?? '',
    tier: data['tier']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    note: data['note']?.toString() ?? '',
    hidden: data['hidden'] == true,
    waitingCheck: data['waitingCheck'] == true,
    untilPlanEnds: data['untilPlanEnds'] == true,
    ownPhoto: data['ownPhoto'] == true,
  );

  final String vendorId, shopId, photoUrl;
  final num price;
  final DateTime endsAt;
  // Owner, 13 Nov 2026: the Vendor ID and plan, the item and the vendor's short text, and the state of the box.
  final String vendorCode, planName, tier, name, note;
  final bool hidden, waitingCheck, untilPlanEnds, ownPhoto;

  /// Where the box is now, in words for the admin.
  String statusAt(DateTime now) {
    if (waitingCheck) return 'Waiting for you: the AI photo check could not run. Show it if the photo is fine';
    if (hidden) return 'Hidden by the office';
    if (!endsAt.isAfter(now)) return untilPlanEnds ? 'Plan ended: hidden until the vendor renews' : 'Ended';
    return untilPlanEnds ? 'Live while the plan runs (until ${premiumDate(endsAt)})' : 'Live until ${premiumDate(endsAt)}';
  }
}

String premiumPrice(num price) => price == price.roundToDouble() ? '₹${price.round()}' : '₹${price.toStringAsFixed(2)}';

String premiumDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
