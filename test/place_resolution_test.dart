// A customer whose location is only a pincode (typed by hand, or saved before towns
// existed) gets a town/district/state from the places directory, so offers made for
// their place reach them -- and offers made for other places never do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'places_fixture.dart';

Entry _offer(String name, String locations) => Entry(name, {
  'name': name,
  'placement': 'carousel',
  'locations': locations,
  'active': true,
  'order': 0,
});

Future<Store> _store(List<Entry> promotions) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['promotions']!.clear();
  for (final promotion in promotions) {
    await store.save('promotions', promotion);
  }
  return store;
}

void main() {
  group('Store.completePlace', () {
    test('a pincode gives its town, district and state', () async {
      final store = await _store([]);
      await store.setLocation('533101', '');
      expect(store.town, isEmpty);
      expect(await store.completePlace(realIndex), isTrue);
      expect([store.town, store.district, store.state], ['Rajahmundry', 'East Godavari', 'Andhra Pradesh']);
      expect(await store.completePlace(realIndex), isFalse, reason: 'nothing left to fill');
      final reopened = Store();
      await reopened.init();
      expect(reopened.district, 'East Godavari', reason: 'saved on the device');
    });

    test('a searched town name gains its district; the pincode picks between same-named towns', () async {
      final store = await _store([]);
      await store.setLocation('516115', 'Rajampet', town: 'Rajampet');
      await store.completePlace(realIndex);
      expect(store.district, 'YSR Kadapa');
      final other = await _store([]);
      await other.setLocation('503110', 'Rajampet', town: 'Rajampet');
      await other.completePlace(realIndex);
      expect(other.district, 'Kamareddy');
      expect(other.state, 'Telangana');
    });

    test('never replaces what the customer picked, and unknown pincodes stay unresolved', () async {
      final store = await _store([]);
      await store.setLocation('533101', 'x', town: 'Somewhere', district: 'Own District', state: 'Own State');
      await store.completePlace(realIndex);
      expect([store.town, store.district, store.state], ['Somewhere', 'Own District', 'Own State']);
      final outside = await _store([]);
      await outside.setLocation('560001', '');
      expect(await outside.completePlace(realIndex), isFalse);
      expect(outside.town, isEmpty);
    });
  });

  group('home page for a pincode-only customer', () {
    setUp(usePlacesFixture);

    testWidgets('sees their own place\'s offers once resolved, never another place\'s', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store([
        _offer('RAJAHMUNDRY OFFER', 'Rajahmundry (East Godavari)'),
        _offer('VIJAYAWADA OFFER', 'Vijayawada (Krishna)'),
      ]);
      await store.setLocation('533101', ''); // a pincode typed by hand: no town yet
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(store.town, 'Rajahmundry', reason: 'resolved from the pincode');
      expect(find.text('RAJAHMUNDRY OFFER'), findsWidgets);
      expect(find.text('VIJAYAWADA OFFER'), findsNothing);
      expect(find.text("Today's Rajahmundry Offers"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('the directory is not fetched when no offer is aimed at a place', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final counter = usePlacesFixture();
      final store = await _store([_offer('EVERYONE', '')]);
      await store.setLocation('533101', '');
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(counter.fetches(), 0, reason: 'the home page stays as light as before');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
