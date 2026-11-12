import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/ist_time.dart';
import 'package:ecommerce_app/domain/reach.dart';

// The ten sample ads of scripts/seed-samples.cjs ("Ad Sample 1".."Ad Sample 10") over five towns, with different timers, each linked
// to its own shop. Distance only (owner, 11 Nov 2026): an ad is shown ONLY to customers within the admin's one km of its shop, whatever
// the ad's own old radius says, and only between its start and end. Checked with the code the website and the apps use (liveAds +
// the shops within reach): at the shop, just inside and just outside the edge in 16 directions, 400 random points each, the five town
// centres, and the moments around the start and the end.

const towns = <String, ({double lat, double lng})>{
  'Narsipatnam': (lat: 17.6670, lng: 82.6120),
  'Tuni': (lat: 17.3590, lng: 82.5460),
  'Rajahmundry': (lat: 17.0005, lng: 81.8040),
  'Visakhapatnam': (lat: 17.6868, lng: 83.2185),
  'Vijayawada': (lat: 16.5062, lng: 80.6480),
};

/// A point [km] from ([lat], [lng]) in direction [bearing] (radians), on the same sphere distanceKm uses.
({double lat, double lng}) moved(double lat, double lng, double km, double bearing) {
  const r = 6371.0;
  final d = km / r, p1 = lat * pi / 180, l1 = lng * pi / 180;
  final p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(bearing));
  final l2 = l1 + atan2(sin(bearing) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2));
  return (lat: p2 * 180 / pi, lng: l2 * 180 / pi);
}

({double lat, double lng}) near(String town, double dLatKm, double dLngKm) {
  final t = towns[town]!;
  return (lat: t.lat + dLatKm / 111, lng: t.lng + dLngKm / (111 * cos(t.lat * pi / 180)));
}

void main() {
  // "Now" for the checks; the timers are set around it like the sample script does.
  final now = DateTime.utc(2026, 11, 6, 6, 0);
  String at(Duration d) => istIso(now.add(d));
  const h = Duration(hours: 1), day = Duration(days: 1), min = Duration(minutes: 1);
  final plan = [
    // centre, radius km, start, end
    (near('Narsipatnam', 0.6, 0.4), 25, -h, day * 7),
    (near('Narsipatnam', -0.8, 1.1), 50, Duration.zero, day * 3),
    (near('Tuni', 0.5, 0.7), 25, Duration.zero, day * 5),
    (near('Rajahmundry', 0.8, 0.5), 50, Duration.zero, day * 10),
    (near('Visakhapatnam', 0.7, -0.6), 25, -day * 3, -day), // already expired
    (near('Visakhapatnam', -1.0, 0.8), 50, -h, min * 2), // ends in 2 minutes
    (near('Vijayawada', 0.9, 0.6), 25, -h, min), // ends in 1 minute
    (near('Vijayawada', -0.7, -1.1), 50, min * 3, day * 2), // starts in 3 minutes
    (near('Rajahmundry', -1.2, 1.0), 25, Duration.zero, day * 6),
    (near('Tuni', -0.9, -0.6), 50, Duration.zero, day * 4),
  ];
  // The admin's one km (Settings > Business Profile).
  const km = 25.0;
  final shops = [
    for (final (i, (c, _, _, _)) in plan.indexed) Entry('shop${i + 1}', {'name': 'Shop ${i + 1}', 'latitude': c.lat, 'longitude': c.lng}),
  ];
  final ads = [
    for (final (i, (c, r, s, e)) in plan.indexed)
      Entry('ad${i + 1}', {
        // The ad's own old radius is still saved, and no longer decides anything.
        'title': 'Ad Sample ${i + 1}', 'status': 'approved', 'active': true, 'imageUrl': 'x', 'contentType': 'image',
        'radiusKm': r, 'radiusLat': c.lat, 'radiusLng': c.lng, 'radiusShopId': 'shop${i + 1}', 'startsAt': at(s), 'endsAt': at(e),
      }),
  ];
  Set<String> shownAt(double lat, double lng, DateTime t) {
    final inReach = shopIdsWithin(shops, lat, lng, km);
    return {for (final a in liveAds(customerAds(ads), t, reaches: (ad) => inReach.contains(linkedShopId(ad)))) a.text('title')};
  }

  test('every ad shows within the admin km of its shop and never outside it (16 directions at the shop, just inside, just outside)', () {
    var checks = 0;
    for (final ad in ads) {
      final lat = ad.number('radiusLat'), lng = ad.number('radiusLng'), r = km;
      // Checked while the ad is running (its own middle of the window), so only the circle decides here.
      final start = parseIstTime(ad.text('startsAt'))!, end = parseIstTime(ad.text('endsAt'))!;
      final t = start.add(end.difference(start) ~/ 2);
      final title = ad.text('title');
      expect(shownAt(lat, lng, t), contains(title), reason: '$title at its centre');
      checks++;
      for (var i = 0; i < 16; i++) {
        final b = i * pi / 8;
        for (final (km, inside) in [(r - 1, true), (r - .05, true), (r + .05, false), (r + 1, false), (r * 3, false)]) {
          final p = moved(lat, lng, km, b);
          expect(shownAt(p.lat, p.lng, t).contains(title), inside, reason: '$title at ${km.toStringAsFixed(2)} km, direction $i');
          checks++;
        }
      }
    }
    // ignore: avoid_print
    print('distance edge checks: $checks, all correct');
  });

  test('400 random places per ad: shown exactly when the place is within the admin km of its shop', () {
    final rnd = Random(20261106);
    var checks = 0, inside = 0;
    for (final ad in ads) {
      final lat = ad.number('radiusLat'), lng = ad.number('radiusLng'), r = km;
      final start = parseIstTime(ad.text('startsAt'))!, end = parseIstTime(ad.text('endsAt'))!;
      final t = start.add(end.difference(start) ~/ 2);
      for (var i = 0; i < 400; i++) {
        final p = moved(lat, lng, rnd.nextDouble() * r * 2, rnd.nextDouble() * 2 * pi);
        final expected = distanceKm(p.lat, p.lng, lat, lng) <= r;
        expect(shownAt(p.lat, p.lng, t).contains(ad.text('title')), expected);
        checks++;
        if (expected) inside++;
      }
    }
    // ignore: avoid_print
    print('random checks: $checks ($inside inside, ${checks - inside} outside), all correct');
  });

  test('the ads each town sees now (the five town centres): only those of shops within the km, live now', () {
    final expected = {
      'Narsipatnam': {'Ad Sample 1', 'Ad Sample 2'},
      'Tuni': {'Ad Sample 3', 'Ad Sample 10'},
      'Rajahmundry': {'Ad Sample 4', 'Ad Sample 9'},
      // Ad 5 has ended; Ad 6 is still running (it ends in 2 minutes).
      'Visakhapatnam': {'Ad Sample 6'},
      // Ad 7 is still running (ends in 1 minute); Ad 8 starts in 3 minutes.
      'Vijayawada': {'Ad Sample 7'},
    };
    for (final MapEntry(key: town, value: c) in towns.entries) {
      final shown = shownAt(c.lat, c.lng, now);
      // ignore: avoid_print
      print('$town: ${(shown.toList()..sort()).join(', ')}');
      expect(shown, expected[town], reason: town);
    }
  });

  test('timers: an ad shows only from its start to its end, by the given (server) time', () {
    final v = towns['Vijayawada']!, z = towns['Visakhapatnam']!;
    // Ad 7 ends 1 minute after "now": shown 1 second before, gone at the end and after.
    expect(shownAt(v.lat, v.lng, now.add(const Duration(seconds: 59))), contains('Ad Sample 7'));
    expect(shownAt(v.lat, v.lng, now.add(min)), isNot(contains('Ad Sample 7')));
    expect(shownAt(v.lat, v.lng, now.add(min * 30)), isNot(contains('Ad Sample 7')));
    // Ad 8 starts 3 minutes after "now": not before, shown from then on.
    expect(shownAt(v.lat, v.lng, now.add(const Duration(minutes: 2, seconds: 59))), isNot(contains('Ad Sample 8')));
    expect(shownAt(v.lat, v.lng, now.add(min * 3)), contains('Ad Sample 8'));
    // Ad 6 ends after 2 minutes; Ad 5 ended yesterday and never comes back.
    expect(shownAt(z.lat, z.lng, now.add(min * 2)), isNot(contains('Ad Sample 6')));
    for (final t in [now, now.add(day), now.subtract(day * 2)]) {
      expect(shownAt(z.lat, z.lng, t).contains('Ad Sample 5'), t.isBefore(now.subtract(day)) && !t.isBefore(now.subtract(day * 3)));
    }
    // The admin's status labels follow the same clock.
    expect(adStatus(ads[4], now), 'expired');
    expect(adStatus(ads[7], now), 'scheduled');
    expect(adStatus(ads[7], now.add(min * 3)), 'live');
    expect(adStatus(ads[6], now.add(min)), 'expired');
  });

  test('a saved time without a zone is India time on every phone; one with a zone is that moment', () {
    expect(parseIstTime('2026-11-06T10:00:00'), DateTime.utc(2026, 11, 6, 4, 30));
    expect(parseIstTime('2026-11-06T10:00:00+05:30'), DateTime.utc(2026, 11, 6, 4, 30));
    expect(parseIstTime('2026-11-06T04:30:00.000Z'), DateTime.utc(2026, 11, 6, 4, 30));
    expect(istIso(DateTime.utc(2026, 11, 6, 4, 30)), '2026-11-06T10:00:00+05:30');
    expect(istLabel(DateTime.utc(2026, 11, 6, 4, 30)), '6 Nov 2026, 10:00 am');
  });
}
