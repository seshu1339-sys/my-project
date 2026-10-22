import 'dart:math' as math;

import 'catalog.dart';

// ---------------------------------------------------------------------------------------------
// ONE radius system for the right-side Ads and for Today's Offers (and any other promotion): the same fields, the same rule.
//
//   radiusKm        one of 5, 10, 25, 50, 100 (chosen from a list, never typed)
//   radiusShopId    the shop whose saved location is the centre of the circle
//   radiusLat/Lng   that centre, copied from the shop when the ad / offer is saved
//
// The ad / offer is shown ONLY to a customer whose current location is inside the circle. An ad / offer with no radius is not affected.
// Circles of different shops may overlap; every ad whose circle covers the customer is shown once. functions/radius.js is the same rule
// for the server (push notifications, vendor ad approval).
// ---------------------------------------------------------------------------------------------

const radiusOptionsKm = [5, 10, 25, 50, 100];

/// A radius asked for in between (say 20 km) goes to the next bigger option (25 km). Null when it is bigger than the biggest option.
int? nextRadiusOption(double km) {
  for (final option in radiusOptionsKm) {
    if (km <= option) return option;
  }
  return null;
}

bool hasRadius(Entry e) => e.number('radiusKm') > 0;

/// The centre of the circle, or null when it was not saved.
({double lat, double lng})? radiusCentre(Entry e) {
  final lat = e.number('radiusLat'), lng = e.number('radiusLng');
  return lat == 0 && lng == 0 ? null : (lat: lat, lng: lng);
}

/// True when [e] may be shown to a customer at ([lat], [lng]): it has no radius, or the customer is inside its circle. A radius ad without a
/// saved centre, or a customer whose location is not known yet, is not shown (it is meant for people inside the circle only).
bool radiusCovers(Entry e, double? lat, double? lng) {
  if (!hasRadius(e)) return true;
  final centre = radiusCentre(e);
  if (centre == null || lat == null || lng == null) return false;
  return distanceKm(lat, lng, centre.lat, centre.lng) <= e.number('radiusKm');
}

/// The ads / offers that cover the customer, each once (an id is never repeated), in their given order.
List<Entry> coveringCustomer(List<Entry> items, double? lat, double? lng) {
  final seen = <String>{};
  return [for (final e in items) if (radiusCovers(e, lat, lng) && seen.add(e.id)) e];
}

DateTime? _date(Entry e, String key) => DateTime.tryParse(e.text(key));

/// Do the two run at the same time? A missing date means "always".
bool runsTogether(Entry a, Entry b) {
  final aStart = _date(a, 'startsAt'), aEnd = _date(a, 'endsAt'), bStart = _date(b, 'startsAt'), bEnd = _date(b, 'endsAt');
  final startsBeforeOtherEnds = aStart == null || bEnd == null || aStart.isBefore(bEnd);
  final otherStartsBeforeEnd = bStart == null || aEnd == null || bStart.isBefore(aEnd);
  return startsBeforeOtherEnds && otherStartsBeforeEnd;
}

/// Points spread over a circle (its centre and two rings), to see how many other circles cover its area.
List<(double, double)> _samples(double lat, double lng, double radiusKm) {
  final points = <(double, double)>[(lat, lng)];
  final cosLat = math.max(.2, math.cos(lat * math.pi / 180));
  for (final ring in const [.5, .9]) {
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      points.add((lat + radiusKm * ring * math.sin(angle) / 111.0, lng + radiusKm * ring * math.cos(angle) / (111.0 * cosLat)));
    }
  }
  return points;
}

/// How many OTHER live-together ads / offers with a radius already cover the busiest spot of [candidate]'s circle.
int areaLoad(Entry candidate, List<Entry> others) {
  final centre = radiusCentre(candidate);
  if (!hasRadius(candidate) || centre == null) return 0;
  final rivals = [
    for (final o in others)
      if (o.id != candidate.id && o.active && o.text('status', 'approved') == 'approved' && hasRadius(o) && radiusCentre(o) != null && runsTogether(candidate, o)) o,
  ];
  var busiest = 0;
  for (final (lat, lng) in _samples(centre.lat, centre.lng, candidate.number('radiusKm'))) {
    final here = rivals.where((o) => radiusCovers(o, lat, lng)).length;
    if (here > busiest) busiest = here;
  }
  return busiest;
}

/// The message to show when saving [candidate] would put more than [max] ads / offers over the same area (0 = no limit); else null.
String? areaFullMessage(Entry candidate, List<Entry> others, int max) {
  if (max <= 0 || !hasRadius(candidate)) return null;
  final load = areaLoad(candidate, others);
  if (load + 1 <= max) return null;
  return 'This area already has $load ads or offers running at the same time (the limit is $max). Choose a smaller radius, other dates, or raise the limit in the Ads settings.';
}
