// The AP/Telangana places directory: the shipped data file, search, nearest
// town, offer targeting by town/district/state, the customer's location dialog
// (live suggestions, GPS), the admin Location field, and that nothing loads
// until one of them is opened.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/domain/towns.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/services/places_directory.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';
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
      expect(names('Raj').take(5), contains('Rajahmundry'));
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
      expect(ids(const CustomerPlace()), ['town', 'district', 'state', 'multi', 'everyone']);
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
      expect(store.latitude, isNull, reason: 'a picked town stays in pincode mode');
      expect(store.address, 'Rajahmundry, East Godavari');
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
    testWidgets('a district-wide and a state-wide offer reach the right customers', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store([
        const Entry('a', {'name': 'EAST GODAVARI WIDE', 'placement': 'carousel', 'locations': 'district:East Godavari', 'active': true, 'order': 0}),
        const Entry('b', {'name': 'TELANGANA WIDE', 'placement': 'carousel', 'locations': 'state:Telangana', 'active': true, 'order': 1}),
      ]);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      await store.setLocation('533101', 'Rajahmundry, East Godavari', town: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh');
      await tester.pump();
      expect(find.text('EAST GODAVARI WIDE'), findsWidgets);
      expect(find.text('TELANGANA WIDE'), findsNothing);
      expect(find.text("Today's Rajahmundry Offers"), findsOneWidget);
      await store.setLocation('506002', 'Warangal, Warangal Urban', town: 'Warangal', district: 'Warangal Urban', state: 'Telangana');
      await tester.pump();
      expect(find.text('TELANGANA WIDE'), findsWidgets);
      expect(find.text('EAST GODAVARI WIDE'), findsNothing);
      expect(find.text("Today's Warangal Offers"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
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

  group('admin Location field', () {
    late ({int Function() fetches}) counter;
    setUp(() => counter = usePlacesFixture());

    testWidgets('search towns, whole districts and whole states; pick several; leave empty for all', (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'promotions')));
      await tester.pump();
      expect(counter.fetches(), 0, reason: 'opening the editor must not download the list');
      await tester.enterText(find.widgetWithText(TextFormField, 'Headline / ticker text'), 'Diwali');
      final search = find.byKey(const ValueKey('place-search'));
      await tester.ensureVisible(search);

      Future<void> pick(String query, Key result) async {
        await tester.enterText(search, query);
        await tester.pump();
        await tester.pump();
        final row = find.byKey(result);
        expect(row, findsOneWidget, reason: query);
        await tester.ensureVisible(row);
        tester.widget<ListTile>(row).onTap!();
        await tester.pump();
      }

      await pick('Raj', const ValueKey('place-result-Rajahmundry-533101'));
      expect(counter.fetches(), 1);
      await pick('East God', const ValueKey('place-area-district:East Godavari'));
      await pick('Telan', const ValueKey('place-area-state:Telangana'));
      final field = tester.widget<TextFormField>(find.byKey(const ValueKey('locations-text')));
      expect(field.controller!.text, 'Rajahmundry (East Godavari), district:East Godavari, state:Telangana');
      expect(find.byKey(const ValueKey('location-token-state:Telangana')), findsOneWidget);
      expect(find.byKey(const ValueKey('location-token-district:East Godavari')), findsOneWidget);

      // Removing a chip removes just that place.
      final chip = find.byKey(const ValueKey('location-token-state:Telangana'));
      tester.widget<InputChip>(chip).onDeleted!();
      await tester.pump();
      expect(field.controller!.text, 'Rajahmundry (East Godavari), district:East Godavari');

      await tester.scrollUntilVisible(
        find.text('Save changes'),
        300,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final saved = store.entries('promotions').firstWhere((e) => e.text('name') == 'Diwali');
      expect(saved.text('locations'), 'Rajahmundry (East Godavari), district:East Godavari');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('a new offer left blank shows everywhere', (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'promotions')));
      await tester.pump();
      expect(find.text('Nothing chosen: this shows in every town.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });
}
