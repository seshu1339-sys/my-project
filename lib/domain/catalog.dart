import 'dart:math';

typedef Json = Map<String, dynamic>;

class Entry {
  final String id;
  final Json data;
  const Entry(this.id, this.data);
  // An explicit empty string (e.g. an admin form field left blank) means
  // "not set", same as a missing key — it must not shadow a real fallback
  // such as text('unit', 'each').
  String text(String key, [String fallback = '']) {
    final value = data[key]?.toString();
    return value == null || value.isEmpty ? fallback : value;
  }
  double number(String key, [double fallback = 0]) => (data[key] is num)
      ? (data[key] as num).toDouble()
      : double.tryParse(text(key)) ?? fallback;
  bool get active => data['active'] != false;
  bool visibleAt(DateTime now) {
    final start = DateTime.tryParse(text('startsAt'));
    final end = DateTime.tryParse(text('endsAt'));
    return active &&
        (start == null || !now.isBefore(start)) &&
        (end == null || now.isBefore(end));
  }

  double price(String pincode) {
    final prices = data['prices'];
    return prices is Map && prices[pincode] is num
        ? (prices[pincode] as num).toDouble()
        : number('price');
  }
}

double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  double radians(double value) => value * pi / 180;
  final a =
      pow(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) *
          cos(radians(lat2)) *
          pow(sin(radians(lon2 - lon1) / 2), 2);
  return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a.clamp(0, 1)));
}

/// A closed ring of points (lat, lng); the last point implicitly connects
/// back to the first. Used for both rectangle targets (as a 4-corner ring)
/// and polygon targets.
typedef GeoRing = List<(double, double)>;

/// Reads a `targetPolygon` field (a list of `{lat, lng}` maps, as saved by
/// the admin's geo-target picker) into a ring. Tolerant of malformed/partial
/// entries — a bad admin edit must never crash matching, it should just fail
/// to match (treated as no polygon).
GeoRing? parsePolygonField(Object? raw) {
  if (raw is! List) return null;
  final ring = <(double, double)>[];
  for (final point in raw) {
    if (point is! Map) return null;
    final lat = point['lat'];
    final lng = point['lng'];
    if (lat is! num || lng is! num) return null;
    ring.add((lat.toDouble(), lng.toDouble()));
  }
  return ring.length >= 3 ? ring : null;
}

/// Reads a `targetRectangle` field (`{north, south, east, west}`, as saved by
/// the admin's geo-target picker) into a normalized bounds map, or null if
/// malformed/absent.
Map<String, double>? parseRectangleField(Object? raw) {
  if (raw is! Map) return null;
  final values = <String, double>{};
  for (final key in ['north', 'south', 'east', 'west']) {
    final value = raw[key];
    if (value is! num) return null;
    values[key] = value.toDouble();
  }
  return values;
}

/// Converts a rectangle bounds map into its 4-corner ring, so rectangle and
/// polygon overlap/containment can share one implementation.
GeoRing rectangleRing(Map<String, double> rectangle) => [
  (rectangle['north']!, rectangle['west']!),
  (rectangle['north']!, rectangle['east']!),
  (rectangle['south']!, rectangle['east']!),
  (rectangle['south']!, rectangle['west']!),
];

bool pointInRectangle(double lat, double lng, Map<String, double> rectangle) =>
    lat <= rectangle['north']! &&
    lat >= rectangle['south']! &&
    lng <= rectangle['east']! &&
    lng >= rectangle['west']!;

/// Standard PNPOLY ray-casting point-in-polygon test. The ring is treated as
/// closed (its last point connects back to its first).
bool pointInPolygon(double lat, double lng, GeoRing ring) {
  if (ring.length < 3) return false;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final (latI, lngI) = ring[i];
    final (latJ, lngJ) = ring[j];
    if ((latI > lat) != (latJ > lat) &&
        lng < (lngJ - lngI) * (lat - latI) / (latJ - latI) + lngI) {
      inside = !inside;
    }
  }
  return inside;
}

/// True when a promotion's optional location targeting allows it to reach
/// this customer. A promotion with no location targeting at all (the default
/// for every promotion today, and — like every other optional numeric field
/// in this app, e.g. dimensionFields' "0 = automatic" — what the admin form
/// saves for a coordinate left blank) is untargeted and shown everywhere.
///
/// `geoShape` selects how the target is interpreted: an absent/missing
/// `geoShape` field means `'circle'`, exactly reproducing every promotion
/// saved before shape-based targeting existed (backward compatible with no
/// migration needed). `'rectangle'`/`'polygon'` read their own dedicated
/// fields (`targetRectangle`/`targetPolygon`) instead of the circle fields.
/// A shape target the customer's GPS can't be checked against (no GPS fix
/// yet) does not fall back to matching by pincode — area targeting means
/// area, not a coincidentally equal pincode.
bool promotionMatchesLocation(
  Entry promotion, {
  required String customerPincode,
  double? customerLatitude,
  double? customerLongitude,
}) {
  final targetPincode = promotion.text('targetPincode');
  final geoShape = promotion.text('geoShape', 'circle');
  final targetLatitude = promotion.number('targetLatitude');
  final targetLongitude = promotion.number('targetLongitude');
  final hasRadiusTarget = geoShape == 'circle' && (targetLatitude != 0 || targetLongitude != 0);
  final rectangle = geoShape == 'rectangle' ? parseRectangleField(promotion.data['targetRectangle']) : null;
  final polygon = geoShape == 'polygon' ? parsePolygonField(promotion.data['targetPolygon']) : null;
  final hasShapeTarget = hasRadiusTarget || rectangle != null || polygon != null;
  if (targetPincode.isEmpty && !hasShapeTarget) return true;
  if (hasShapeTarget) {
    if (customerLatitude == null || customerLongitude == null) return false;
    if (rectangle != null) return pointInRectangle(customerLatitude, customerLongitude, rectangle);
    if (polygon != null) return pointInPolygon(customerLatitude, customerLongitude, polygon);
    final radiusKm = promotion.number('targetRadiusKm');
    return distanceKm(
          customerLatitude,
          customerLongitude,
          targetLatitude,
          targetLongitude,
        ) <=
        (radiusKm > 0 ? radiusKm : 10);
  }
  return customerPincode.isNotEmpty && customerPincode == targetPincode;
}

double _toRadians(double value) => value * pi / 180;

/// Shortest distance in km from a point to a line segment, using a flat-Earth
/// (equirectangular) approximation local to the point's latitude. Accurate at
/// neighbourhood/city scale (this app's actual use case); not valid for
/// segments spanning hundreds of km or near the poles.
double distancePointToSegmentKm(
  double lat,
  double lng,
  (double, double) a,
  (double, double) b,
) {
  final cosLat = cos(_toRadians(lat));
  final px = lng * cosLat, py = lat;
  final ax = a.$2 * cosLat, ay = a.$1;
  final bx = b.$2 * cosLat, by = b.$1;
  final dx = bx - ax, dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  final t = lengthSquared == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
  final closestX = ax + t * dx, closestY = ay + t * dy;
  final degrees = sqrt(pow(px - closestX, 2) + pow(py - closestY, 2));
  return degrees * 111.32; // km per degree of latitude, a standard constant.
}

bool _segmentsIntersect(
  (double, double) p1,
  (double, double) p2,
  (double, double) p3,
  (double, double) p4,
) {
  double orientation((double, double) a, (double, double) b, (double, double) c) =>
      (b.$2 - a.$2) * (c.$1 - b.$1) - (b.$1 - a.$1) * (c.$2 - b.$2);
  bool onSegment((double, double) a, (double, double) b, (double, double) c) =>
      c.$1 <= max(a.$1, b.$1) && c.$1 >= min(a.$1, b.$1) && c.$2 <= max(a.$2, b.$2) && c.$2 >= min(a.$2, b.$2);
  final o1 = orientation(p1, p2, p3);
  final o2 = orientation(p1, p2, p4);
  final o3 = orientation(p3, p4, p1);
  final o4 = orientation(p3, p4, p2);
  if ((o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)) return true;
  if (o1 == 0 && onSegment(p1, p2, p3)) return true;
  if (o2 == 0 && onSegment(p1, p2, p4)) return true;
  if (o3 == 0 && onSegment(p3, p4, p1)) return true;
  if (o4 == 0 && onSegment(p3, p4, p2)) return true;
  return false;
}

/// True when two rectangle/polygon target areas (each already reduced to a
/// ring — see [rectangleRing]) spatially overlap. A pragmatic test, not a
/// rigorous computational-geometry library: it catches partial overlap (any
/// pair of edges crossing) and full containment either direction (any vertex
/// of one ring inside the other). Self-intersecting admin-drawn polygons are
/// not specially detected or rejected.
bool ringsOverlap(GeoRing a, GeoRing b) {
  for (var i = 0; i < a.length; i++) {
    final a1 = a[i], a2 = a[(i + 1) % a.length];
    for (var j = 0; j < b.length; j++) {
      final b1 = b[j], b2 = b[(j + 1) % b.length];
      if (_segmentsIntersect(a1, a2, b1, b2)) return true;
    }
  }
  if (a.isNotEmpty && pointInPolygon(a.first.$1, a.first.$2, b)) return true;
  if (b.isNotEmpty && pointInPolygon(b.first.$1, b.first.$2, a)) return true;
  return false;
}

/// True when a circle target area overlaps a rectangle/polygon ring.
bool circleOverlapsRing(double lat, double lng, double radiusKm, GeoRing ring) {
  if (pointInPolygon(lat, lng, ring)) return true;
  for (var i = 0; i < ring.length; i++) {
    if (distancePointToSegmentKm(lat, lng, ring[i], ring[(i + 1) % ring.length]) <= radiusKm) {
      return true;
    }
  }
  return false;
}

({double lat, double lng, double radiusKm})? _circleOf(Entry promotion) {
  if (promotion.text('geoShape', 'circle') != 'circle') return null;
  final lat = promotion.number('targetLatitude');
  final lng = promotion.number('targetLongitude');
  if (lat == 0 && lng == 0) return null;
  final radiusKm = promotion.number('targetRadiusKm');
  return (lat: lat, lng: lng, radiusKm: radiusKm > 0 ? radiusKm : 10);
}

GeoRing? _ringOf(Entry promotion) {
  final shape = promotion.text('geoShape', 'circle');
  if (shape == 'rectangle') {
    final rectangle = parseRectangleField(promotion.data['targetRectangle']);
    return rectangle == null ? null : rectangleRing(rectangle);
  }
  if (shape == 'polygon') return parsePolygonField(promotion.data['targetPolygon']);
  return null;
}

/// True when two promotions' geo-target areas spatially overlap — used by
/// the admin geo-target picker to warn about a possible double booking.
/// Untargeted promotions (reach everyone, but aren't a "booked zone") never
/// overlap anything, matching how untargeted and targeted promotions already
/// coexist with no conflict today.
bool promotionShapesOverlap(Entry a, Entry b) {
  final circleA = _circleOf(a), circleB = _circleOf(b);
  final ringA = _ringOf(a), ringB = _ringOf(b);
  if (circleA != null && circleB != null) {
    return distanceKm(circleA.lat, circleA.lng, circleB.lat, circleB.lng) <=
        circleA.radiusKm + circleB.radiusKm;
  }
  if (circleA != null && ringB != null) {
    return circleOverlapsRing(circleA.lat, circleA.lng, circleA.radiusKm, ringB);
  }
  if (circleB != null && ringA != null) {
    return circleOverlapsRing(circleB.lat, circleB.lng, circleB.radiusKm, ringA);
  }
  if (ringA != null && ringB != null) return ringsOverlap(ringA, ringB);
  return false;
}

const collections = [
  'products',
  'categories',
  'shops',
  'promotions',
  'settings',
  'productImageLibrary',
  'vendorShopPhotos',
];

Map<String, List<Entry>> demoCatalog() => {
  'settings': [
    const Entry('business', {
      'name': 'Local Market',
      'tagline': 'Everyday shopping made easy.',
      'address': 'Your online storefront',
      'phone': '+91 90000 00000',
      'radiusKm': 10,
      'active': true,
    }),
    const Entry('scrollingText', {
      'name': 'Scrolling text',
      'text': '',
      'textColor': '#FFFFFF',
      'backgroundColor': '#174C38',
      'fontSize': 12,
      'fontWeight': 400,
      'speed': 70,
      'height': 36,
      'padding': 9,
      'active': true,
    }),
    const Entry('theme', {'name': 'Theme', 'mode': 'light', 'active': true}),
  ],
  'categories': [
    for (final (i, name) in [
      'Fresh & daily',
      'Home & living',
      'Electronics',
      'Local services',
      'Pantry',
    ].indexed)
      Entry('c$i', {'name': name, 'order': i, 'active': true, 'parentId': ''}),
  ],
  'shops': [
    const Entry('s1', {
      'name': 'The Corner Store',
      'address': 'MG Road, Bengaluru',
      'phone': '+91 90000 00001',
      'latitude': 12.9716,
      'longitude': 77.5946,
      'pincode': '560001',
      'radiusKm': 10,
      'description': 'Everyday essentials from your neighbourhood.',
      'active': true,
    }),
    const Entry('s2', {
      'name': 'Home Helpers',
      'address': 'Indiranagar, Bengaluru',
      'phone': '+91 90000 00002',
      'latitude': 12.9784,
      'longitude': 77.6408,
      'pincode': '560038',
      'radiusKm': 15,
      'description': 'Skilled local professionals for your home.',
      'active': true,
    }),
  ],
  'products': [
    for (final (i, item) in <(String, String, double, String)>[
      (
        'Farm-fresh vegetable box',
        'c0',
        249,
        'A colourful selection of seasonal vegetables. Packed fresh by your local shop.',
      ),
      (
        'Everyday ceramic mug',
        'c1',
        349,
        'A warm companion for your morning coffee. 350 ml ceramic mug.',
      ),
      (
        'Wireless headphones',
        'c2',
        1499,
        'Comfortable everyday listening with a rechargeable battery.',
      ),
      (
        'Organic pantry essentials',
        'c4',
        599,
        'Stock your kitchen with a thoughtful selection of daily essentials.',
      ),
      (
        'Plumbing visit',
        'c3',
        299,
        'Book an inspection. Materials and additional work quoted separately.',
      ),
      (
        'Electrician visit',
        'c3',
        349,
        'Local electrical inspection and service consultation.',
      ),
      (
        'Mason consultation',
        'c3',
        499,
        'Discuss repairs and renovation with a local professional.',
      ),
      (
        'Labour assistance',
        'c3',
        699,
        'Daily assistance. Confirm scope and duration with the provider.',
      ),
    ].indexed)
      Entry('p$i', {
        'name': item.$1,
        'categoryId': item.$2,
        'price': item.$3,
        'description': item.$4,
        'kind': i >= 4 ? 'service' : 'product',
        'shopId': i >= 4 ? 's2' : 's1',
        'stock': 30,
        'order': i,
        'active': true,
        'imageUrl': '',
        'prices': {'560001': item.$3},
        'unit': i >= 4 ? 'per visit' : 'each',
      }),
  ],
  'promotions': [
    const Entry('welcome', {
      'name': 'Everyday essentials, ready when you are.',
      'description':
          'Shop products and trusted services from one convenient storefront.',
      'placement': 'carousel',
      'target': 'category:c0',
      'order': 0,
      'active': true,
    }),
    const Entry('local', {
      'name': 'A little closer. A lot better.',
      'description':
          'Browse the collection and find something useful for today.',
      'placement': 'carousel',
      'target': 'shops',
      'order': 1,
      'active': true,
    }),
    const Entry('ticker', {
      'name': 'SHOP LOCAL • Fresh picks every day • Trusted services in your neighbourhood',
      'placement': 'ticker',
      'order': 0,
      'active': true,
    }),
    const Entry('ad', {
      'name': 'A helping hand, nearby.',
      'description': 'Plumbers, electricians and more. Find your local expert.',
      'placement': 'ad',
      'target': 'category:c3',
      'width': 260,
      'height': 280,
      'order': 0,
      'active': true,
    }),
    const Entry('ad2', {
      'name': 'Fast delivery, every day.',
      'description': 'Order before 6pm for same-day delivery from local shops.',
      'placement': 'ad',
      'target': 'shops',
      'width': 260,
      'height': 200,
      'order': 1,
      'active': true,
    }),
    const Entry('ad3', {
      'name': 'Secure payments.',
      'description': 'Pay on delivery or online, your choice, every time.',
      'placement': 'ad',
      'target': 'category:c1',
      'width': 260,
      'height': 200,
      'order': 2,
      'active': true,
    }),
    const Entry('box', {
      'name': 'Your daily essentials, sorted.',
      'description': 'Explore the pantry collection',
      'placement': 'box',
      'target': 'category:c4',
      'height': 160,
      'order': 1,
      'active': true,
    }),
  ],
  'productImageLibrary': [],
  'vendorShopPhotos': [],
};
