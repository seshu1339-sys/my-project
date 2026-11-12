// Unit tests for the shape geometry helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';

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
  // Who sees an offer on the real page is decided by its shop's distance only (owner, 11 Nov 2026): see
  // test/promotion_location_test.dart. The shape helpers above are still used by the admin's area tools.
}
