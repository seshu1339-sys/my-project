// Unit tests for the shape geometry helpers, plus real-app coverage that
// rectangle/polygon-targeted promotions actually reach only customers inside
// their area — same "render the real MarketApp" precedent already
// established in promotion_location_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

// A simple square, roughly 1 degree on a side, centred near the equator so
// degree-to-km math stays easy to reason about.
const _square = <(double, double)>[(1, 1), (1, 2), (2, 2), (2, 1)];

void main() {
  group('pointInPolygon', () {
    test('a point inside a convex ring is inside', () {
      expect(pointInPolygon(1.5, 1.5, _square), isTrue);
    });
    test('a point outside a convex ring is outside', () {
      expect(pointInPolygon(5, 5, _square), isFalse);
    });
    test('a point inside a concave (L-shaped) ring is inside', () {
      const lShape = <(double, double)>[(0, 0), (0, 3), (1, 3), (1, 1), (3, 1), (3, 0)];
      expect(pointInPolygon(0.5, 0.5, lShape), isTrue); // inside the "L"
      expect(pointInPolygon(2, 2, lShape), isFalse); // inside the notch, not the shape
    });
    test('fewer than 3 points is never inside', () {
      expect(pointInPolygon(1, 1, const [(0, 0), (1, 1)]), isFalse);
    });
  });

  group('pointInRectangle', () {
    const box = {'north': 2.0, 'south': 1.0, 'east': 2.0, 'west': 1.0};
    test('inside the box', () => expect(pointInRectangle(1.5, 1.5, box), isTrue));
    test('outside the box', () => expect(pointInRectangle(5, 5, box), isFalse));
    test('exactly on the boundary counts as inside', () => expect(pointInRectangle(2.0, 1.5, box), isTrue));
  });

  group('ringsOverlap', () {
    test('partially overlapping squares', () {
      const other = <(double, double)>[(1.5, 1.5), (1.5, 2.5), (2.5, 2.5), (2.5, 1.5)];
      expect(ringsOverlap(_square, other), isTrue);
    });
    test('disjoint squares do not overlap', () {
      const far = <(double, double)>[(10, 10), (10, 11), (11, 11), (11, 10)];
      expect(ringsOverlap(_square, far), isFalse);
    });
    test('one ring fully containing another still overlaps (containment, no crossing edges)', () {
      const big = <(double, double)>[(0, 0), (0, 10), (10, 10), (10, 0)];
      const small = <(double, double)>[(4, 4), (4, 5), (5, 5), (5, 4)];
      expect(ringsOverlap(big, small), isTrue);
      expect(ringsOverlap(small, big), isTrue); // symmetric regardless of argument order
    });
    test('touching (sharing an edge) counts as overlapping', () {
      const adjacent = <(double, double)>[(1, 2), (1, 3), (2, 3), (2, 2)];
      expect(ringsOverlap(_square, adjacent), isTrue);
    });
  });

  group('circleOverlapsRing', () {
    test('circle centered inside the ring overlaps', () {
      expect(circleOverlapsRing(1.5, 1.5, 1, _square), isTrue);
    });
    test('circle far away with a small radius does not overlap', () {
      expect(circleOverlapsRing(20, 20, 1, _square), isFalse);
    });
    test('circle just touching a ring edge overlaps', () {
      // ~111km per degree; a point 0.5 degrees (~55km) west of the square's
      // west edge, with a 60km radius, should just reach it.
      expect(circleOverlapsRing(1.5, 0.5, 60, _square), isTrue);
      expect(circleOverlapsRing(1.5, 0.5, 40, _square), isFalse);
    });
  });

  group('promotionShapesOverlap', () {
    test('two overlapping circles', () {
      const a = Entry('a', {'geoShape': 'circle', 'targetLatitude': 12.97, 'targetLongitude': 77.59, 'targetRadiusKm': 10});
      const b = Entry('b', {'geoShape': 'circle', 'targetLatitude': 12.98, 'targetLongitude': 77.60, 'targetRadiusKm': 10});
      expect(promotionShapesOverlap(a, b), isTrue);
    });
    test('two distant circles do not overlap', () {
      const a = Entry('a', {'geoShape': 'circle', 'targetLatitude': 12.97, 'targetLongitude': 77.59, 'targetRadiusKm': 5});
      const b = Entry('b', {'geoShape': 'circle', 'targetLatitude': 20.0, 'targetLongitude': 80.0, 'targetRadiusKm': 5});
      expect(promotionShapesOverlap(a, b), isFalse);
    });
    test('a circle and an overlapping rectangle', () {
      const circle = Entry('a', {'geoShape': 'circle', 'targetLatitude': 1.5, 'targetLongitude': 1.5, 'targetRadiusKm': 10});
      const rect = Entry('b', {
        'geoShape': 'rectangle',
        'targetRectangle': {'north': 2.0, 'south': 1.0, 'east': 2.0, 'west': 1.0},
      });
      expect(promotionShapesOverlap(circle, rect), isTrue);
    });
    test('a polygon and a rectangle', () {
      const polygon = Entry('a', {
        'geoShape': 'polygon',
        'targetPolygon': [
          {'lat': 1.0, 'lng': 1.0},
          {'lat': 1.0, 'lng': 3.0},
          {'lat': 3.0, 'lng': 3.0},
          {'lat': 3.0, 'lng': 1.0},
        ],
      });
      const rect = Entry('b', {
        'geoShape': 'rectangle',
        'targetRectangle': {'north': 2.0, 'south': 1.5, 'east': 2.0, 'west': 1.5},
      });
      expect(promotionShapesOverlap(polygon, rect), isTrue);
    });
    test('an untargeted promotion never overlaps anything', () {
      const untargeted = Entry('a', {'name': 'Everywhere ad'});
      const circle = Entry('b', {'geoShape': 'circle', 'targetLatitude': 1.5, 'targetLongitude': 1.5, 'targetRadiusKm': 10});
      expect(promotionShapesOverlap(untargeted, circle), isFalse);
      expect(promotionShapesOverlap(circle, untargeted), isFalse);
    });
  });

  testWidgets('a rectangle-targeted promotion only shows to a customer inside it', (tester) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['promotions']?.clear();
    await store.save(
      'promotions',
      const Entry('promo1', {
        'name': 'Inside the box',
        'placement': 'carousel',
        'geoShape': 'rectangle',
        'targetRectangle': {'north': 13.0, 'south': 12.9, 'east': 77.7, 'west': 77.5},
      }),
    );
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Inside the box'), findsNothing);

    await store.setLocation('', 'Outside', lat: 20.0, lng: 80.0);
    await tester.pump();
    expect(find.text('Inside the box'), findsNothing);

    await store.setLocation('', 'Inside', lat: 12.95, lng: 77.6);
    await tester.pump();
    expect(find.text('Inside the box'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a polygon-targeted promotion only shows to a customer inside it', (tester) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['promotions']?.clear();
    await store.save(
      'promotions',
      const Entry('promo2', {
        'name': 'Inside the triangle',
        'placement': 'carousel',
        'geoShape': 'polygon',
        'targetPolygon': [
          {'lat': 12.90, 'lng': 77.50},
          {'lat': 13.00, 'lng': 77.50},
          {'lat': 12.95, 'lng': 77.70},
        ],
      }),
    );
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();

    await store.setLocation('', 'Outside', lat: 20.0, lng: 80.0);
    await tester.pump();
    expect(find.text('Inside the triangle'), findsNothing);

    await store.setLocation('', 'Inside', lat: 12.95, lng: 77.55);
    await tester.pump();
    expect(find.text('Inside the triangle'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a promotion saved before shape-targeting existed (no geoShape field) still matches as a circle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['promotions']?.clear();
    // No 'geoShape' key at all — simulates a doc saved before this phase.
    await store.save(
      'promotions',
      const Entry('legacy', {
        'name': 'Legacy circle ad',
        'placement': 'carousel',
        'targetLatitude': 12.9716,
        'targetLongitude': 77.5946,
        'targetRadiusKm': 5,
      }),
    );
    await store.setLocation('', 'Nearby', lat: 12.99, lng: 77.60);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Legacy circle ad'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
