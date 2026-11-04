/// A subscription plan as the admin made it (a `vendorPlans` document).
class SubscriptionPlan {
  const SubscriptionPlan({required this.id, required this.name, required this.price, required this.durationMonths, required this.active});

  factory SubscriptionPlan.fromData(String id, Map<String, dynamic> data) => SubscriptionPlan(
    id: id,
    name: data['name']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    durationMonths: (data['durationMonths'] as num?)?.toInt() ?? 0,
    active: data['active'] == true,
  );

  final String id, name;
  final num price;
  final int durationMonths;
  final bool active;
}

/// The vendor's latest plan (their `vendorPlanStatus` document); null when they never had one.
class VendorPlanStatus {
  const VendorPlanStatus({required this.planName, required this.endsAt});
  final String planName;
  final DateTime endsAt;

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
