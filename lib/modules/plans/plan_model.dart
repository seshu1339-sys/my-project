import 'package:cloud_firestore/cloud_firestore.dart';

/// Items (each with its photos) a vendor may have without a plan, and on a plan, unless the admin sets other numbers
/// (planServiceGates/main.freeItemLimit and vendorPlans/{id}.itemLimit; the same defaults as functions/modules/plans/rules.js).
const defaultFreeItemLimit = 2;
const defaultPlanItemLimit = 10;

/// Paid plans come in three kinds; they differ only in extra photos and km (functions/modules/plans/rules.js).
// Platinum and Diamond were added on 13 Nov 2026; a new kind only needs a line here and in functions/modules/plans/rules.js.
const planTiers = <String, String>{'silver': 'Silver', 'gold': 'Gold', 'platinum': 'Platinum', 'diamond': 'Diamond', 'premium': 'Premium'};
/// The km a plan can reach, as the admin picks them (the existing choices).
const planRadiusChoices = <int>[5, 10, 25, 50, 100];
const defaultPlanExtraPhotos = 10;
const defaultPlanRadiusKm = 25.0;
/// Today's Offers boxes a plan gives unless the admin sets the plan's own number (owner, 13 Nov 2026): Silver 1, Gold 2, Platinum 4, Diamond 6, Premium 5.
const defaultOfferBoxes = <String, int>{'silver': 1, 'gold': 2, 'platinum': 4, 'diamond': 6, 'premium': 5};
const maxOfferBoxes = 20;
// Every vendor has one shop photo (not counted) and, on the free plan, this many extra photos.
const freeExtraPhotos = 2;

/// What every paid plan gives, whatever its kind.
const paidPlanServices = ['Sudden offer alerts to nearby customers', "Your box in Today's Offers", 'Your box in the website\'s ad boxes', 'Advanced help chat, with a direct line to the office'];

String kmText(double km) => '${km == km.roundToDouble() ? km.toInt() : km} km';

int? _count(Object? v) => v is num && v == v.roundToDouble() && v >= 0 && v <= 100 ? v.toInt() : null;

/// The free plan's item limit from the planServiceGates/main document.
int freeItemLimit(Map<String, dynamic>? gates) => _count(gates?['freeItemLimit']) ?? defaultFreeItemLimit;

/// The free plan's extra photos (planServiceGates/main.freeExtraPhotos), besides the shop photo.
int freeExtraPhotosOf(Map<String, dynamic>? gates) => _count(gates?['freeExtraPhotos']) ?? freeExtraPhotos;

/// A subscription plan as the admin made it (a `vendorPlans` document).
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMonths,
    required this.active,
    this.itemLimit = defaultPlanItemLimit,
    this.tier = 'premium',
    this.extraPhotos = defaultPlanExtraPhotos,
    this.radiusKm = defaultPlanRadiusKm,
    int? offerBoxes,
  }) : offerBoxes = offerBoxes ?? (tier == 'silver' ? 1 : tier == 'gold' ? 2 : tier == 'platinum' ? 4 : tier == 'diamond' ? 6 : 5);

  factory SubscriptionPlan.fromData(String id, Map<String, dynamic> data) => SubscriptionPlan(
    id: id,
    name: data['name']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    durationMonths: (data['durationMonths'] as num?)?.toInt() ?? 0,
    active: data['active'] == true,
    itemLimit: _count(data['itemLimit']) ?? defaultPlanItemLimit,
    tier: planTiers.containsKey(data['tier']) ? data['tier'] as String : 'premium',
    extraPhotos: _count(data['extraPhotos']) ?? defaultPlanExtraPhotos,
    radiusKm: (data['radiusKm'] as num?)?.toDouble() ?? defaultPlanRadiusKm,
    offerBoxes: _count(data['offerBoxes']),
  );

  // How many Today's Offers boxes the vendor gets on this plan.
  final int offerBoxes;
  // Silver, Gold or Premium; the extra photos the vendor may have and how far (km) their ad and offer reach users.
  final String tier;
  final int extraPhotos;
  final double radiusKm;
  final String id, name;
  final num price;
  final int durationMonths;
  final bool active;
  // How many items (each with its photos) a vendor may have while this plan runs.
  final int itemLimit;
}

/// The vendor's latest plan (their `vendorPlanStatus` document); null when they never had one.
class VendorPlanStatus {
  const VendorPlanStatus({required this.planName, required this.endsAt, this.tier = '', this.itemLimit = defaultPlanItemLimit, this.uid = '', this.vendorName = '', this.vendorCode = '', this.byAdmin = false, this.renewedAt, this.byPayment = false});

  factory VendorPlanStatus.fromData(String uid, Map<String, dynamic> data) {
    final endsAt = data['endsAt'];
    return VendorPlanStatus(
      uid: uid,
      planName: data['planName']?.toString() ?? '',
      tier: data['tier']?.toString() ?? '',
      endsAt: endsAt is Timestamp ? endsAt.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      itemLimit: _count(data['itemLimit']) ?? defaultPlanItemLimit,
      vendorName: data['vendorName']?.toString() ?? '',
      vendorCode: data['vendorCode']?.toString() ?? '',
      byAdmin: data['source'] == 'admin',
      byPayment: data['source'] == 'payment',
      renewedAt: switch (data['updatedAt']) { final Timestamp t => t.toDate(), _ => null },
    );
  }

  final String planName;
  // Silver, Gold, Platinum, Diamond or Premium (empty on old statuses).
  final String tier;
  final DateTime endsAt;
  final int itemLimit;
  // For the admin's list: whose plan it is, and whether the admin started or stopped it by hand.
  final String uid, vendorName, vendorCode;
  final bool byAdmin;
  // The last start or renewal: a verified payment renews by itself (functions/modules/plans activatePlan), or the admin by hand.
  final bool byPayment;
  final DateTime? renewedAt;

  /// "Renewed by payment on 13/11/2026", "Started by admin on ...", or '' when unknown.
  String get renewalText {
    final when = renewedAt;
    if (when == null) return '';
    final date = '${when.day}/${when.month}/${when.year}';
    return byPayment ? 'Renewed by payment on $date' : byAdmin ? 'Changed by admin on $date' : 'Updated on $date';
  }

  bool activeAt(DateTime now) => endsAt.isAfter(now);
}

/// The special services a plan can unlock. The keys are the same as SERVICES in functions/modules/plans/rules.js.
const planServices = <String, String>{
  'vendorAds': 'My Ads (send an ad for the shop)',
  'rightBoxAds': 'Ad for your shop (Right Side Ad Boxes)',
  'exclusives': 'Special Category Exclusives',
};

/// Plans in the order a vendor compares them: shortest first, then cheapest.
List<SubscriptionPlan> sortedPlans(Iterable<SubscriptionPlan> plans) => plans.toList()
  ..sort((a, b) {
    final months = a.durationMonths.compareTo(b.durationMonths);
    return months != 0 ? months : a.price.compareTo(b.price);
  });

String planDuration(int months) {
  if (months % 12 == 0) {
    final years = months ~/ 12;
    return years == 1 ? '1 year' : '$years years';
  }
  return months == 1 ? '1 month' : '$months months';
}

/// Exactly the price the admin set: no decimals for a whole number.
String planPrice(num price) => price == price.roundToDouble() ? '₹${price.toInt()}' : '₹${price.toStringAsFixed(2)}';

String planDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
