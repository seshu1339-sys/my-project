// The admin's own ads made by command (owner spec D, 17 Nov 2026): "this photo, Today's Offers, Narsipatnam, 10 km, 2 days".
//
//   adminAds/<id>  {title, photoUrl, placement: todaysOffers | rightBox | both, kind: photo | rate, productName,
//                   reach: radius | town | district | state | allIndia, latitude, longitude, radiusKm, town, district, state,
//                   startsAt, endsAt (ISO, UTC), active, createdBy, createdAt}
//
// Owner decisions: town / district / state / All India are for ADMIN ads only (vendor offers and ads stay km-only, lib/domain/reach.dart).
// An admin ad simply JOINS the rotation of its place (Today's Offers boxes or the right-side ad boxes): no priority, it takes its turn
// with the vendors' boxes. A "live rate" ad shows an item's lowest price in the customer's area at the moment it is seen.
import 'dart:math' as math;

import 'agent_command.dart';

enum AdminAdPlacement { todaysOffers, rightBox, both }

class AdminAd {
  const AdminAd({
    required this.id,
    this.title = '',
    this.photoUrl = '',
    this.placement = AdminAdPlacement.todaysOffers,
    this.kind = 'photo',
    this.productName = '',
    this.reach = AdReach.radius,
    this.latitude,
    this.longitude,
    this.radiusKm = 10,
    this.town = '',
    this.district = '',
    this.state = '',
    this.startsAt,
    this.endsAt,
    this.active = true,
  });

  final String id, title, photoUrl, kind, productName, town, district, state;
  final AdminAdPlacement placement;
  final AdReach reach;
  final double? latitude, longitude;
  final double radiusKm;
  final DateTime? startsAt, endsAt;
  final bool active;

  bool get isRate => kind == 'rate';
  bool showsIn(AdminAdPlacement where) => placement == AdminAdPlacement.both || placement == where;

  factory AdminAd.from(String id, Map<String, dynamic> d) => AdminAd(
    id: id,
    title: '${d['title'] ?? ''}',
    photoUrl: '${d['photoUrl'] ?? ''}',
    placement: AdminAdPlacement.values.where((p) => p.name == d['placement']).firstOrNull ?? AdminAdPlacement.todaysOffers,
    kind: d['kind'] == 'rate' ? 'rate' : 'photo',
    productName: '${d['productName'] ?? ''}',
    reach: AdReach.values.where((r) => r.name == d['reach']).firstOrNull ?? AdReach.radius,
    latitude: (d['latitude'] as num?)?.toDouble(),
    longitude: (d['longitude'] as num?)?.toDouble(),
    radiusKm: (d['radiusKm'] as num?)?.toDouble() ?? 10,
    town: '${d['town'] ?? ''}',
    district: '${d['district'] ?? ''}',
    state: '${d['state'] ?? ''}',
    startsAt: DateTime.tryParse('${d['startsAt'] ?? ''}'),
    endsAt: DateTime.tryParse('${d['endsAt'] ?? ''}'),
    active: d['active'] != false,
  );

  Map<String, dynamic> toData() => {
    'title': title,
    'photoUrl': photoUrl,
    'placement': placement.name,
    'kind': kind,
    'productName': productName,
    'reach': reach.name,
    'latitude': ?latitude,
    'longitude': ?longitude,
    'radiusKm': radiusKm,
    'town': town,
    'district': district,
    'state': state,
    'startsAt': startsAt?.toUtc().toIso8601String() ?? '',
    'endsAt': endsAt?.toUtc().toIso8601String() ?? '',
    'active': active,
  };

  AdminAd copyWith({String? title, String? photoUrl, AdminAdPlacement? placement, String? kind, String? productName, AdReach? reach, double? latitude, double? longitude, double? radiusKm, String? town, String? district, String? state, DateTime? startsAt, DateTime? endsAt}) => AdminAd(
    id: id,
    title: title ?? this.title,
    photoUrl: photoUrl ?? this.photoUrl,
    placement: placement ?? this.placement,
    kind: kind ?? this.kind,
    productName: productName ?? this.productName,
    reach: reach ?? this.reach,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    radiusKm: radiusKm ?? this.radiusKm,
    town: town ?? this.town,
    district: district ?? this.district,
    state: state ?? this.state,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    active: active,
  );

  bool liveAt(DateTime now) => active && (startsAt == null || !now.isBefore(startsAt!)) && (endsAt == null || now.isBefore(endsAt!));

  /// What is missing before it can go live ('' when it is ready).
  String get missing {
    if (isRate ? productName.trim().isEmpty : photoUrl.isEmpty && title.trim().isEmpty) return isRate ? 'Choose the item whose live rate shows.' : 'Add a photo or a text.';
    if (endsAt == null || (startsAt != null && !endsAt!.isAfter(startsAt!))) return 'Choose how long it runs.';
    return switch (reach) {
      AdReach.radius => latitude == null || longitude == null ? 'Choose the place (its location) for the km.' : radiusKm <= 0 ? 'The km must be above 0.' : '',
      AdReach.town => town.trim().isEmpty ? 'Choose the town.' : '',
      AdReach.district => district.trim().isEmpty ? 'Choose the district.' : '',
      AdReach.state => state.trim().isEmpty ? 'Choose the state.' : '',
      AdReach.allIndia => '',
    };
  }

  /// "Narsipatnam · 10 km · 2 days" — what the preview and the list say.
  String get reachLabel => switch (reach) {
    AdReach.radius => '${town.isEmpty ? 'Around the point' : town} · ${_n(radiusKm)} km',
    AdReach.town => 'Town: $town',
    AdReach.district => 'District: $district',
    AdReach.state => 'State: $state',
    AdReach.allIndia => 'All India',
  };
}

String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double _km(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
  return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Whether a customer at this place sees [ad]: within the km of its point, in its town / district / state, or anywhere (All India).
bool adminAdReaches(AdminAd ad, {double? lat, double? lng, String town = '', String district = '', String state = ''}) => switch (ad.reach) {
  AdReach.allIndia => true,
  AdReach.radius => lat != null && lng != null && ad.latitude != null && ad.longitude != null && !(lat == 0 && lng == 0) && _km(lat, lng, ad.latitude!, ad.longitude!) <= ad.radiusKm,
  AdReach.town => ad.town.isNotEmpty && _norm(ad.town) == _norm(town),
  AdReach.district => ad.district.isNotEmpty && _norm(ad.district) == _norm(district),
  AdReach.state => ad.state.isNotEmpty && _norm(ad.state) == _norm(state),
};

/// The admin ads one customer sees now in [where], in a fixed order (by id) so they mix into the rotation without going first.
List<AdminAd> adminAdsFor(Iterable<AdminAd> ads, AdminAdPlacement where, DateTime now, {double? lat, double? lng, String town = '', String district = '', String state = ''}) => [
  for (final a in ads)
    if (a.showsIn(where) && a.liveAt(now) && adminAdReaches(a, lat: lat, lng: lng, town: town, district: district, state: state)) a,
]..sort((a, b) => a.id.compareTo(b.id));

/// One rotation queue with no priority: [admin] ads go in among [vendors] at a stable place each (it depends only on the ad's own key),
/// so an admin ad is neither always first nor always last, and the vendors keep their own order.
List<T> mixQueue<T>(List<T> vendors, List<T> admin, String Function(T) key) {
  int h(String s) {
    var x = 0x811c9dc5;
    for (final c in s.codeUnits) {
      x = ((x ^ c) * 0x01000193) & 0xffffffff;
    }
    // A finishing mix, so every letter of the key moves the place (not only the last ones).
    x ^= x >> 16;
    x = (x * 0x85ebca6b) & 0xffffffff;
    x ^= x >> 13;
    x = (x * 0xc2b2ae35) & 0xffffffff;
    return x ^ (x >> 16);
  }
  final out = [...vendors];
  for (final a in admin) {
    out.insert(h(key(a)) % (out.length + 1), a);
  }
  return out;
}

/// The ad the command asked for, as far as the words tell (the form fills in the rest). [now] is when it starts.
AdminAd adminAdFromCommand(AgentCommand c, {required DateTime now, String photoUrl = ''}) {
  final days = c.days ?? (c.hours == null ? 1 : 0);
  final ends = now.add(Duration(days: days, hours: c.hours ?? 0));
  final reach = c.reach ?? (c.place.isNotEmpty ? AdReach.radius : AdReach.radius);
  return AdminAd(
    id: '',
    kind: c.intent == AgentIntent.rate ? 'rate' : 'photo',
    photoUrl: photoUrl,
    placement: c.placement == 'rightBox' ? AdminAdPlacement.rightBox : AdminAdPlacement.todaysOffers,
    reach: reach,
    radiusKm: c.km ?? 10,
    town: c.place,
    district: reach == AdReach.district ? c.place : '',
    state: reach == AdReach.state ? c.place : '',
    startsAt: now,
    endsAt: ends,
  );
}
