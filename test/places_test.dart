// The places directory of India: the shipped data files (one per state), search, nearest
// town, offer targeting by town/district/state, the customer's location dialog
// (live suggestions, GPS), the admin Location field, and that nothing loads
// until one of them is opened.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/domain/towns.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/services/location_town.dart';
import 'package:ecommerce_app/services/places_directory.dart';
import 'package:ecommerce_app/ui/location_picker_dialog.dart';
import 'places_fixture.dart';

Position _at(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 20),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Future<Store> _store([List<Entry> promotions = const []]) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['promotions']!.clear();
  for (final promotion in promotions) {
    await store.save('promotions', promotion);
  }
  return store;
}

Widget _opener(Store store, {Future<Position> Function()? locate}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showLocationPickerDialog(context, store, locate: locate),
          child: const Text('open'),
        ),
      ),
    );

void main() {
  group('all of India, a state at a time', () {
    test('the index lists every state and union territory, each with its file', () {
      expect(realManifest.states.length, 36);
      for (final name in ['Andhra Pradesh', 'Telangana', 'Karnataka', 'Tamil Nadu', 'Maharashtra', 'Delhi', 'Ladakh', 'Lakshadweep']) {
        expect(realManifest.named(name), isNotNull, reason: name);
      }
      for (final state in realManifest.states) {
        expect(File('web/data/${state.file}').existsSync(), isTrue, reason: state.file);
        expect(state.districts, isNotEmpty, reason: state.name);
        expect(state.pinPrefixes, isNotEmpty, reason: state.name);
      }
    });

    test('every state file holds only its own state, with valid pincodes', () {
      for (final state in realManifest.states) {
        final index = PlacesIndex.fromJson(
          jsonDecode(placesFileNamed(state.file)) as Map<String, dynamic>,
        );
        expect(index.states, [state.name]);
        expect(index.length, greaterThan(5), reason: state.name);
        expect(index.places.every((p) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(p.pincode)), isTrue, reason: state.name);
        expect(
          index.places.every((p) => state.pinPrefixes.contains(int.parse(p.pincode.substring(0, 2)))),
          isTrue,
          reason: state.name,
        );
      }
    });

    test('a GPS fix or a pincode points at the right state', () {
      expect(realManifest.statesAt(12.97, 77.59).map((s) => s.name), contains('Karnataka'));
      expect(realManifest.statesAt(13.08, 80.27).map((s) => s.name), contains('Tamil Nadu'), reason: 'Chennai');
      expect(realManifest.statesAt(19.07, 72.88).map((s) => s.name), contains('Maharashtra'), reason: 'Mumbai');
      expect(realManifest.statesAt(28.61, 77.21).map((s) => s.name), contains('Delhi'));
      expect(realManifest.statesAt(0, 0), isEmpty, reason: 'the Gulf of Guinea');
      expect(realManifest.statesForPincode('560001').map((s) => s.name), contains('Karnataka'));
      expect(realManifest.statesForPincode('533101').map((s) => s.name), contains('Andhra Pradesh'));
      expect(realManifest.statesForPincode('50001'), isEmpty);
      expect(realManifest.statesForPincode('abcdef'), isEmpty);
    });

    test('the admin finds districts and states anywhere in India', () {
      expect(realManifest.searchAreas('karnat').map((a) => a.token), contains('state:Karnataka'));
      expect(realManifest.searchAreas('bengaluru').map((a) => a.token), contains('district:Bengaluru Urban'));
      expect(realManifest.searchAreas('x'), isEmpty);
    });

    test('states are downloaded when asked for, once each, and joined', () async {
      final counter = usePlacesFixture();
      final directory = PlacesDirectory.instance;
      expect(directory.ready, isNull);
      final karnataka = await directory.load(states: ['Karnataka']);
      expect(karnataka.states, ['Karnataka']);
      expect(counter.fetches(), 1);
      expect(karnataka.nearestTown(12.97, 77.59)?.state, 'Karnataka');
      final both = await directory.load(states: ['Karnataka', 'Kerala']);
      expect(both.states, ['Karnataka', 'Kerala']);
      expect(counter.fetches(), 2, reason: 'Karnataka was already loaded');
      expect(both.byPincode('560001')?.town, 'Bengaluru');
      expect(both.byPincode('695001')?.state, 'Kerala');
      final gps = await directory.loadForPoint(17.385, 78.486);
      expect(gps.nearestTown(17.385, 78.486)?.district, 'Hyderabad');
      expect(gps.states, contains('Telangana'));
      await expectLater(directory.loadForPoint(0, 0), throwsStateError);
      await expectLater(directory.load(states: ['Atlantis']), throwsStateError);
    });
  });

  group('the shipped file', () {
    test('covers Andhra Pradesh and Telangana, towns and villages', () {
      expect(realIndex.states, ['Andhra Pradesh', 'Telangana']);
      expect(realIndex.length, greaterThan(15000));
      expect(realIndex.districts.length, greaterThan(40));
      expect(realIndex.places.where((p) => !p.village).length, greaterThan(2000));
      expect(
        realIndex.places.every((p) => RegExp(r'^[5][0-9]{5}$').hasMatch(p.pincode)),
        isTrue,
        reason: 'AP/Telangana pincodes all start with 5',
      );
      expect(
        realIndex.places.every((p) => p.name.trim().isNotEmpty && p.district.isNotEmpty),
        isTrue,
      );
    });

    test('typing part of a name or a pincode finds the town', () {
      List<String> names(String q) =>
          realIndex.search(q).map((p) => p.name).toList();
      expect(names('Raj').first, 'Rajahmundry', reason: 'the big city before smaller towns');
      expect(names('rajahm').first, 'Rajahmundry');
      expect(names('533101').first, 'Rajahmundry');
      expect(names('Vijayaw').first, 'Vijayawada');
      expect(names('Hyderabad'), contains('Hyderabad'));
      expect(names('Narsipat').first, 'Narsipatnam');
      // Three digits is enough to start suggesting pincodes.
      expect(realIndex.search('5331'), isNotEmpty);
      expect(realIndex.search('53'), isEmpty);
      expect(realIndex.search('zzzzqq'), isEmpty);
      // Towns come before villages for the same text.
      final results = realIndex.search('Rajah', limit: 8);
      expect(results.first.village, isFalse);
    });

    test('a sub-office belongs to its head office\'s town', () {
      final alcot = realIndex.search('Alcot Gardens').first;
      expect(alcot.town, 'Rajahmundry');
      expect(alcot.district, 'East Godavari');
      expect(alcot.state, 'Andhra Pradesh');
      final rajahmundry = realIndex.search('533101').firstWhere((p) => p.name == 'Rajahmundry');
      expect(rajahmundry.label, 'Rajahmundry, East Godavari');
    });

    test('districts and states can be searched as areas', () {
      expect(
        realIndex.searchAreas('east').map((a) => a.token),
        contains('district:East Godavari'),
      );
      expect(realIndex.searchAreas('telan').map((a) => a.token), contains('state:Telangana'));
      expect(realIndex.searchAreas('andhra').single.token, 'state:Andhra Pradesh');
      expect(realIndex.searchAreas('x'), isEmpty);
    });

    test('GPS finds the nearest town, and nothing outside the two states', () {
      expect(realIndex.nearestTown(16.99, 81.78)!.town, 'Rajahmundry');
      expect(realIndex.nearestTown(16.51, 80.62)!.town, 'Vijayawada');
      expect(realIndex.nearestTown(17.385, 78.486)!.district, 'Hyderabad');
      expect(realIndex.nearestTown(17.573, 82.491)!.town, 'Narsipatnam');
      for (final (name, lat, lng) in [
        ('Tirupati', 13.63, 79.42),
        ('Warangal', 17.98, 79.60),
        ('Kurnool', 15.83, 78.04),
        ('Visakhapatnam', 17.70, 83.30),
        ('Nellore', 14.44, 79.99),
        ('Karimnagar', 18.44, 79.13),
      ]) {
        expect(realIndex.nearestTown(lat, lng)!.town, name, reason: 'GPS in $name');
      }
      expect(realIndex.nearestTown(12.97, 77.59), isNull, reason: 'Bengaluru');
    });

    test('searching stays instant', () {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        realIndex.search(['raj', 'vij', '5201', 'hyd', 'nar'][i % 5]);
      }
      watch.stop();
      expect(watch.elapsedMilliseconds / 50, lessThan(40));
    });
  });

  group('offer targeting', () {
    const rajahmundry = CustomerPlace(
      town: 'Rajahmundry',
      district: 'East Godavari',
      state: 'Andhra Pradesh',
    );
    test('a town, its district, its state, or the old plain name', () {
      bool hit(String token) => locationTokenMatches(token, rajahmundry);
      expect(hit('Rajahmundry (East Godavari)'), isTrue);
      expect(hit('rajahmundry (east godavari)'), isTrue);
      expect(hit('Rajahmundry'), isTrue);
      expect(hit('Rajahmundry (Krishna)'), isFalse, reason: 'same name, other district');
      expect(hit('district:East Godavari'), isTrue);
      expect(hit('district:Krishna'), isFalse);
      expect(hit('state:Andhra Pradesh'), isTrue);
      expect(hit('state:Telangana'), isFalse);
      expect(hit('Vijayawada'), isFalse);
      expect(
        locationTokenMatches('Narsipatnam', const CustomerPlace(town: 'Narsipatnam')),
        isTrue,
        reason: 'offers saved before districts existed keep working',
      );
      expect(locationTokenMatches('district:East Godavari', const CustomerPlace(town: 'X')), isFalse);
    });

    test('empty means every town; a place picks its own, else general', () {
      final all = [
        Entry('town', {'locations': 'Rajahmundry (East Godavari)'}),
        Entry('district', {'locations': 'district:East Godavari'}),
        Entry('state', {'locations': 'state:Telangana'}),
        Entry('multi', {'locations': 'Vijayawada (Krishna), state:Andhra Pradesh'}),
        Entry('everyone', {'locations': ''}),
      ];
      List<String> ids(CustomerPlace p) => promotionsForTown(
        all,
        p.town,
        district: p.district,
        state: p.state,
      ).entries.map((e) => e.id).toList();
      expect(ids(rajahmundry), ['town', 'district', 'multi']);
      expect(ids(const CustomerPlace(town: 'Warangal', district: 'Warangal Urban', state: 'Telangana')), ['state']);
      expect(ids(const CustomerPlace(town: 'Chennai', state: 'Tamil Nadu')), ['everyone']);
      // No location chosen: only the general offers; the ones aimed at places are held back.
      expect(ids(const CustomerPlace()), ['everyone']);
      final held = promotionsForTown(all, '');
      expect(held.hiddenForLocation, 4);
      expect(promotionsForTown(all, '', showAll: true).entries, hasLength(5), reason: 'the admin preview shows everything');
    });

    test('chips read plainly', () {
      expect(describeLocationToken('state:Telangana'), 'All of Telangana');
      expect(describeLocationToken('district:Krishna'), 'All of Krishna district');
      expect(describeLocationToken('Rajahmundry (East Godavari)'), 'Rajahmundry (East Godavari)');
    });
  });

  group('customer location dialog', () {
    late ({int Function() fetches}) counter;
    setUp(() => counter = usePlacesFixture());

    testWidgets('typing a name shows suggestions; tapping one sets the location', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(_opener(store));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('place-search')), 'Raj');
      await tester.pump();
      expect(find.byKey(const ValueKey('place-result-Rajahmundry-533101')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('place-result-Rajahmundry-533101')));
      await tester.pumpAndSettle();
      expect(store.town, 'Rajahmundry');
      expect(store.district, 'East Godavari');
      expect(store.state, 'Andhra Pradesh');
      expect(store.pincode, '533101');
      expect(store.located, isTrue, reason: 'a picked place has its point: what the customer sees is measured from it');
      expect(store.placeName, 'Rajahmundry');
      expect(store.address, isEmpty, reason: 'the typed address is for delivery only; the place name is not written into it');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('typing a pincode finds that town', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(_opener(store));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('place-search')), '533101');
      await tester.pump();
      expect(find.byKey(const ValueKey('place-result-Rajahmundry-533101')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('Use my location picks the nearest town from GPS', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(_opener(store, locate: () async => _at(16.51, 80.62)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(store.town, 'Vijayawada');
      expect(store.district, 'Krishna');
      expect(store.state, 'Andhra Pradesh');
      expect(store.latitude, closeTo(16.51, .001));
      expect(store.pincode, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('the file is fetched when the dialog opens, never with the home page, and only once',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump(const Duration(seconds: 3));
      expect(counter.fetches(), 0, reason: 'the home page must not load the places list');
      expect(PlacesDirectory.instance.ready, isNull);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(_opener(store));
      await tester.pump(const Duration(seconds: 1));
      expect(counter.fetches(), 0);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(counter.fetches(), 1);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(counter.fetches(), 1, reason: 'already loaded: no second download');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('home page offers by district and state', () {
    setUp(usePlacesFixture);
    // District-wide and state-wide offers are gone (owner, 11 Nov 2026): who sees an offer is decided by its shop's distance only
    // (test/promotion_location_test.dart, test/area_location_test.dart).
    test('"Use my location" is remembered and follows the phone; a hand-picked town never does', () async {
      final store = await _store();
      expect(store.followsGps, isFalse);
      await store.setLocation('533101', 'x', town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh', followGps: true);
      expect(store.followsGps, isTrue);
      await store.setLocation('533101', 'x', lat: 16.9, lng: 81.7, followGps: store.followsGps);
      expect(store.followsGps, isTrue);
      final reopened = Store();
      await reopened.init();
      expect(reopened.followsGps, isTrue);
      await reopened.setLocation('520001', 'Vijayawada', town: 'Vijayawada', district: 'Krishna', state: 'Andhra Pradesh');
      expect(reopened.followsGps, isFalse, reason: 'choosing a town by hand stops following the GPS');
      store.dispose();
      reopened.dispose();
    });

    test('products follow their shop by distance, never a town name; an item without a shop shows nowhere', () async {
      final store = await _store();
      store.catalog['shops']!
        ..clear()
        ..addAll(const [
          Entry('s-raj', {'name': 'Rajahmundry shop', 'latitude': 17.0005, 'longitude': 81.804}),
          Entry('s-war', {'name': 'Warangal shop', 'latitude': 17.97, 'longitude': 79.59, 'town': 'Rajahmundry'}),
        ]);
      store.catalog['products']!
        ..clear()
        ..addAll(const [
          Entry('p1', {'name': 'RAJ ITEM', 'town': 'Rajahmundry', 'active': true}),
          Entry('p2', {'name': 'WARANGAL ITEM', 'shopId': 's-war', 'active': true}),
          Entry('p3', {'name': 'RAJ SHOP ITEM', 'shopId': 's-raj', 'active': true}),
          Entry('p4', {'name': 'NOWHERE ITEM', 'active': true}),
        ]);
      expect(store.visibleProducts().length, 4, reason: 'only the demo with no place shows everything');
      await store.setLocation('533101', 'x', lat: 17.0, lng: 81.8, town: 'Rajahmundry');
      expect(store.visibleProducts().map((p) => p.id), ['p3'], reason: "a town name on the product or its shop does not count");
      expect(store.visibleProducts(all: true).length, 4);
      await store.setLocation('506002', 'x', lat: 17.97, lng: 79.6, town: 'Warangal');
      expect(store.visibleProducts().map((p) => p.id), ['p2']);
      store.dispose();
    });

    test('a GPS fix stores the pincode of the nearest town when the typed one is from another town', () async {
      usePlacesFixture();
      await PlacesDirectory.instance.load();
      final raj = realIndex.townNamed('Rajahmundry')!;
      final vij = realIndex.townNamed('Vijayawada')!;
      expect(pincodeForGps('', raj), raj.pincode);
      expect(pincodeForGps(vij.pincode, raj), raj.pincode);
      expect(pincodeForGps(raj.pincode, raj), raj.pincode);
      expect(pincodeForGps('560001', null), '560001');
    });

    test('the district and state survive a restart, and a GPS refresh keeps them', () async {
      final store = await _store();
      await store.setLocation('533101', 'x', town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh');
      await store.setLocation('533101', 'x', lat: 16.9, lng: 81.7);
      expect(store.district, 'East Godavari');
      final reopened = Store();
      await reopened.init();
      expect(reopened.town, 'Rajahmundry');
      expect(reopened.district, 'East Godavari');
      expect(reopened.state, 'Andhra Pradesh');
      store.dispose();
      reopened.dispose();
    });
  });

  // The admin's Location field (towns, districts, states) is gone from the offer form (owner, 11 Nov 2026): an offer is shown near
  // its shop only (test/radius_test.dart, the offer form).
}
