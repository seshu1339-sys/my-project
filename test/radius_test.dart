import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/radius.dart';
import 'package:ecommerce_app/ui/admin_ads.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';

// Narsipatnam is the centre of most circles here; Anakapalle is about 45 km away, Vizag about 100 km.
const narsipatnam = (17.667, 82.612);
const anakapalle = (17.691, 83.003);
const rajahmundry = (17.000, 81.800);

Entry circle(String id, double km, (double, double) centre, [Map<String, dynamic> more = const {}]) =>
    Entry(id, {'title': id, 'contentType': 'text', 'radiusKm': km, 'radiusShopId': 'shop', 'radiusLat': centre.$1, 'radiusLng': centre.$2, ...more});

final monday = DateTime(2026, 10, 26, 10, 30);

void main() {
  group('the radius list', () {
    test('only 5, 10, 25, 50 and 100 km; an in-between radius goes to the next bigger one', () {
      expect(radiusOptionsKm, [5, 10, 25, 50, 100]);
      expect(nextRadiusOption(20), 25);
      expect(nextRadiusOption(25), 25);
      expect(nextRadiusOption(26), 50);
      expect(nextRadiusOption(1), 5);
      expect(nextRadiusOption(101), isNull);
    });
  });

  group('who is inside the circle', () {
    test('inside is shown, outside is not; no radius is not affected', () {
      final ad = circle('a', 10, narsipatnam);
      expect(radiusCovers(ad, 17.67, 82.62), isTrue);
      expect(radiusCovers(ad, anakapalle.$1, anakapalle.$2), isFalse, reason: 'about 45 km away');
      expect(radiusCovers(circle('b', 50, narsipatnam), anakapalle.$1, anakapalle.$2), isTrue);
      expect(radiusCovers(const Entry('plain', {'title': 'x'}), null, null), isTrue, reason: 'no radius: as before, even with no location');
    });

    test('a radius ad is not shown when the customer location is unknown or the centre was never saved', () {
      expect(radiusCovers(circle('a', 10, narsipatnam), null, null), isFalse);
      expect(radiusCovers(const Entry('a', {'radiusKm': 10}), 17.6, 82.6), isFalse);
    });

    test('the edge of the circle is inside', () {
      // 0.1 degrees of latitude is about 11.1 km
      expect(radiusCovers(circle('a', 25, (17.0, 82.0)), 17.1, 82.0), isTrue);
      expect(radiusCovers(circle('a', 5, (17.0, 82.0)), 17.1, 82.0), isFalse);
    });

    test('overlapping circles of different shops all show, each once', () {
      final items = [
        circle('shopA', 25, narsipatnam),
        circle('shopB', 50, anakapalle),
        circle('shopC', 5, rajahmundry),
        circle('shopA', 25, narsipatnam), // the same id twice (a duplicate record)
      ];
      final here = coveringCustomer(items, 17.7, 82.8); // between the two towns
      expect(here.map((e) => e.id), ['shopA', 'shopB']);
      expect(coveringCustomer(items, rajahmundry.$1, rajahmundry.$2).map((e) => e.id), ['shopC']);
    });
  });

  group('Today\'s Offers use the same rule', () {
    test('an offer with a radius reaches only customers inside it, on top of the pincode / area rules', () {
      final offer = circle('offer', 10, narsipatnam, {'placement': 'carousel'});
      bool reaches(double? lat, double? lng, {String pin = ''}) => promotionReaches(offer, customerPincode: pin, customerLatitude: lat, customerLongitude: lng);
      expect(reaches(17.67, 82.62), isTrue);
      expect(reaches(anakapalle.$1, anakapalle.$2), isFalse);
      expect(reaches(null, null), isFalse);
      final withPin = Entry('o2', {...offer.data, 'targetPincode': '531116'});
      expect(promotionReaches(withPin, customerPincode: '531116', customerLatitude: 17.67, customerLongitude: 82.62), isTrue);
      expect(promotionReaches(withPin, customerPincode: '500001', customerLatitude: 17.67, customerLongitude: 82.62), isFalse, reason: 'both rules apply');
    });

    test('offers without a radius behave exactly as before', () {
      const old = Entry('old', {'placement': 'carousel', 'name': 'x'});
      expect(promotionReaches(old, customerPincode: '', customerLatitude: null, customerLongitude: null), isTrue);
    });
  });

  group('ads and offers decide the same way', () {
    final ads = [
      circle('near', 10, narsipatnam),
      circle('wide', 100, narsipatnam),
      circle('far', 5, rajahmundry),
      const Entry('everywhere', {'title': 'x', 'contentType': 'text'}),
    ];

    test('the ads shown follow the customer location', () {
      List<String> at(double? lat, double? lng) => liveAds(ads, monday, latitude: lat, longitude: lng).map((a) => a.id).toList()..sort();
      expect(at(17.67, 82.62), ['everywhere', 'near', 'wide']);
      expect(at(anakapalle.$1, anakapalle.$2), ['everywhere', 'wide'], reason: 'moved 45 km: the 10 km ad drops out');
      expect(at(rajahmundry.$1, rajahmundry.$2), ['everywhere', 'far'], reason: 'moved far away: only the ad around the new place');
      expect(at(null, null), ['everywhere'], reason: 'location unknown: only ads without a radius');
    });

    test('the admin preview shows everything', () {
      expect(liveAds(ads, monday, showAll: true).length, 4);
    });
  });

  group('maximum per area', () {
    test('counts the other ads over the busiest spot of the circle, only when they run at the same time', () {
      final a = circle('a', 25, narsipatnam, {'startsAt': '2026-11-01T00:00:00', 'endsAt': '2026-11-30T00:00:00'});
      final b = circle('b', 25, narsipatnam, {'startsAt': '2026-11-10T00:00:00', 'endsAt': '2026-12-10T00:00:00'});
      final later = circle('later', 25, narsipatnam, {'startsAt': '2026-12-15T00:00:00'});
      final elsewhere = circle('elsewhere', 5, rajahmundry);
      expect(runsTogether(a, b), isTrue);
      expect(runsTogether(a, later), isFalse);
      expect(areaLoad(a, [b, later, elsewhere]), 1);
      expect(areaLoad(a, [a, b]), 1, reason: 'itself is not counted');
      expect(areaLoad(a, const []), 0);
    });

    test('a circle that only touches the edge of another counts it (it covers a sample point)', () {
      final big = circle('big', 100, narsipatnam);
      final small = circle('small', 5, anakapalle);
      expect(areaLoad(small, [big]), 1);
    });

    test('the message appears only when the limit would be passed; 0 means no limit', () {
      final candidate = circle('new', 10, narsipatnam);
      final others = [circle('x', 10, narsipatnam), circle('y', 25, narsipatnam)];
      expect(areaFullMessage(candidate, others, 0), isNull);
      expect(areaFullMessage(candidate, others, 3), isNull);
      expect(areaFullMessage(candidate, others, 2), contains('already has 2'));
      expect(areaFullMessage(const Entry('plain', {}), others, 1), isNull, reason: 'no radius: not part of this limit');
      expect(AdsConfig.from([const Entry('adsConfig', {'maxPerArea': 4})]).maxPerArea, 4);
      expect(AdsConfig.from(const []).maxPerArea, 0);
    });
  });

  group('the ad form', () {
    Future<Store> store({List<Entry> ads = const [], int max = 0}) async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.init();
      s.catalog['ads'] = [...ads];
      s.catalog['promotions'] = [];
      s.catalog['shops'] = const [
        Entry('shop-n', {'name': 'Suma Fresh Mart', 'latitude': 17.667, 'longitude': 82.612, 'order': 1}),
        Entry('shop-x', {'name': 'No location shop', 'order': 2}),
      ];
      if (max > 0) s.catalog['settings'] = [Entry('adsConfig', {'maxPerArea': max})];
      return s;
    }

    Future<void> open(WidgetTester tester, Store s) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAdsPage(store: s))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ad-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text only'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ad-field-title')), 'Sale');
    }

    Future<void> pick(WidgetTester tester, String key, String text) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('ad-save')));
      await tester.tap(find.byKey(const ValueKey('ad-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('the radius comes from a fixed list; the centre is the shop location, filled in automatically', (tester) async {
      final s = await store();
      await open(tester, s);
      await tester.ensureVisible(find.byKey(const ValueKey('ad-radius-')));
      await tester.tap(find.byKey(const ValueKey('ad-radius-')));
      await tester.pumpAndSettle();
      for (final km in ['5 km', '10 km', '25 km', '50 km', '100 km']) {
        expect(find.text(km), findsWidgets, reason: km);
      }
      expect(find.text('20 km'), findsNothing, reason: 'no in-between values');
      await tester.tap(find.text('25 km').last);
      await tester.pumpAndSettle();
      await pick(tester, 'ad-radius-shop-', 'Suma Fresh Mart');
      expect(find.text('Centre: 17.667, 82.612'), findsOneWidget);
      expect(find.text('No location shop'), findsNothing, reason: 'only shops with a saved location can be a centre');
      await save(tester);
      final saved = s.entries('ads').single;
      expect(saved.number('radiusKm'), 25);
      expect(saved.text('radiusShopId'), 'shop-n');
      expect(saved.number('radiusLat'), 17.667);
      expect(saved.number('radiusLng'), 82.612);
    });

    testWidgets('a radius without a shop is refused', (tester) async {
      final s = await store();
      await open(tester, s);
      await tester.ensureVisible(find.byKey(const ValueKey('ad-radius-')));
      await tester.tap(find.byKey(const ValueKey('ad-radius-')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 km').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Choose the shop whose location is the centre of the radius.'), findsOneWidget);
      expect(s.entries('ads'), isEmpty);
    });

    testWidgets('removing the radius removes the centre too', (tester) async {
      final s = await store(ads: [circle('old', 10, narsipatnam, {'order': 1, 'radiusShopId': 'shop-n'})]);
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: AdEditorPage(store: s, ad: s.entries('ads').single)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ad-radius-10')));
      await tester.tap(find.byKey(const ValueKey('ad-radius-10')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No radius').last);
      await tester.pumpAndSettle();
      await save(tester);
      final saved = s.entries('ads').single;
      expect(saved.data.containsKey('radiusKm'), isFalse);
      expect(saved.data.containsKey('radiusLat'), isFalse);
    });

    testWidgets('the maximum per area stops one more ad over a full area', (tester) async {
      final s = await store(max: 1, ads: [circle('existing', 25, narsipatnam, {'order': 1})]);
      await open(tester, s);
      await tester.ensureVisible(find.byKey(const ValueKey('ad-radius-')));
      await tester.tap(find.byKey(const ValueKey('ad-radius-')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 km').last);
      await tester.pumpAndSettle();
      await pick(tester, 'ad-radius-shop-', 'Suma Fresh Mart');
      await save(tester);
      expect(find.textContaining('already has 1 ads or offers'), findsOneWidget);
      expect(s.entries('ads').length, 1, reason: 'nothing new was saved');
    });
  });

  group('the offer form (Today\'s Offers)', () {
    Future<Store> store({int max = 0, List<Entry> offers = const []}) async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.init();
      s.catalog['ads'] = [];
      s.catalog['promotions'] = [...offers];
      s.catalog['shops'] = const [Entry('shop-n', {'name': 'Suma Fresh Mart', 'latitude': 17.667, 'longitude': 82.612, 'order': 1})];
      if (max > 0) s.catalog['settings'] = [Entry('adsConfig', {'maxPerArea': max})];
      return s;
    }

    Future<void> show(WidgetTester tester, Store s) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: s, collection: 'promotions')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Headline / ticker text'), 'Diwali offer');
    }

    Finder dropdown(String label) => find.ancestor(of: find.text(label), matching: find.byType(DropdownButtonFormField<String>)).first;

    Future<void> choose(WidgetTester tester, String label, String text) async {
      await tester.ensureVisible(dropdown(label));
      await tester.tap(dropdown(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    testWidgets('has the same Radius list and shop centre, and saves them like an ad does', (tester) async {
      final s = await store();
      await show(tester, s);
      await choose(tester, 'Display location', 'carousel');
      await choose(tester, 'Radius (shown only to customers inside this circle)', '50 km');
      await choose(tester, 'Radius centre — the shop whose saved location is the middle of the circle', 'Suma Fresh Mart');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = s.entries('promotions').single;
      expect(saved.number('radiusKm'), 50);
      expect(saved.text('radiusShopId'), 'shop-n');
      expect(saved.number('radiusLat'), 17.667);
      expect(saved.number('radiusLng'), 82.612);
    });

    testWidgets('no radius chosen: nothing changes for the offer', (tester) async {
      final s = await store();
      await show(tester, s);
      await choose(tester, 'Display location', 'carousel');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = s.entries('promotions').single;
      expect(hasRadius(saved), isFalse);
      expect(saved.data.containsKey('radiusLat'), isFalse);
    });

    testWidgets('a radius without a shop is refused', (tester) async {
      final s = await store();
      await show(tester, s);
      await choose(tester, 'Display location', 'carousel');
      await choose(tester, 'Radius (shown only to customers inside this circle)', '10 km');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(s.entries('promotions'), isEmpty);
      expect(find.textContaining('Choose the shop whose location is the centre'), findsOneWidget);
    });

    testWidgets('the same maximum per area applies to offers', (tester) async {
      final s = await store(max: 1, offers: [circle('existing', 25, narsipatnam, {'placement': 'carousel', 'order': 1})]);
      await show(tester, s);
      await choose(tester, 'Display location', 'carousel');
      await choose(tester, 'Radius (shown only to customers inside this circle)', '10 km');
      await choose(tester, 'Radius centre — the shop whose saved location is the middle of the circle', 'Suma Fresh Mart');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(s.entries('promotions').length, 1);
      expect(find.textContaining('already has 1 ads or offers'), findsOneWidget);
    });
  });
}
