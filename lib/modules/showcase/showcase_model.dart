import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/store.dart';

/// Showcase module (functions/modules/showcase): each paid vendor's box in Today's Offers and in the website's right-side ad boxes, seen
/// only by customers within the plan's km. A `vendorShowcase` document.
class ShowcaseEntry {
  const ShowcaseEntry({required this.vendorId, required this.shopId, required this.shopName, required this.photoUrl, required this.radiusKm, required this.active, this.endsAt});

  factory ShowcaseEntry.fromData(String id, Map<String, dynamic> d) => ShowcaseEntry(
    vendorId: id,
    shopId: d['shopId']?.toString() ?? '',
    shopName: d['shopName']?.toString() ?? '',
    photoUrl: d['photoUrl']?.toString() ?? '',
    radiusKm: (d['radiusKm'] as num?)?.toDouble() ?? 25,
    active: d['active'] == true,
    endsAt: (d['endsAt'] as Timestamp?)?.toDate(),
  );

  final String vendorId, shopId, shopName, photoUrl;
  final double radiusKm;
  final bool active;
  final DateTime? endsAt;

  bool liveAt(DateTime now) => active && (endsAt == null || endsAt!.isAfter(now));
}

double _km(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
  return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Whether a customer at ([lat], [lng]) is within the vendor's plan km of their shop. Without a known place on either side: no.
bool withinReach(ShowcaseEntry entry, {double? lat, double? lng, double? shopLat, double? shopLng}) {
  bool known(double? v) => v != null && v != 0;
  if (!known(lat) || !known(lng) || !known(shopLat) || !known(shopLng)) return false;
  return _km(lat!, lng!, shopLat!, shopLng!) <= entry.radiusKm;
}

/// Which boxes show now. With more vendors than [visible] boxes, they take turns, [visible] at a time, each turn [seconds] long. With
/// as many or fewer, every other turn shows [fillers] instead, so no vendor's box stays on longer than [seconds] (owner, 6 Nov 2026).
List<T> rotationPage<T>(List<T> items, {required int visible, required int seconds, required DateTime now, List<T> fillers = const []}) {
  if (visible <= 0) return const [];
  if (items.isEmpty) return fillers.take(visible).toList();
  final turn = now.millisecondsSinceEpoch ~/ (math.max(1, seconds) * 1000);
  if (items.length <= visible) return turn.isEven ? items : fillers.take(visible).toList();
  final pages = (items.length / visible).ceil();
  return items.skip((turn % pages) * visible).take(visible).toList();
}

/// When the boxes change next.
Duration untilNextTurn(int seconds, DateTime now) {
  final ms = math.max(1, seconds) * 1000;
  return Duration(milliseconds: ms - now.millisecondsSinceEpoch % ms);
}

/// The live showcase records (public), by vendor.
Stream<Map<String, ShowcaseEntry>> watchShowcase(Store store) =>
    store.firestore.collection('vendorShowcase').where('active', isEqualTo: true).snapshots().map((s) => {for (final d in s.docs) d.id: ShowcaseEntry.fromData(d.id, d.data())});
