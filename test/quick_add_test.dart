import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/domain/quick_items.dart';
import 'package:ecommerce_app/ui/admin_search.dart';
import 'package:ecommerce_app/ui/quick_add.dart';
import 'package:ecommerce_app/ui/quick_admin.dart';
import 'package:ecommerce_app/ui/quick_fresh.dart';
import 'places_fixture.dart';

final _now = DateTime(2026, 10, 21, 9, 0);

Future<Store> _store({bool extraPlace = false}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['categories'] = [
    for (var i = 0; i < 24; i++) Entry('cat-$i', {'name': 'Category $i', 'order': i, 'parentId': ''}),
  ];
  if (extraPlace) {
    store.catalog['locations'] = const [
      Entry('loc-mkt', {'name': 'Old Market', 'town': 'Rajahmundry', 'order': 0}),
      Entry('loc-off', {'name': 'Closed', 'order': 1, 'active': false}),
    ];
  }
  return store;
}

Entry _item(String id, {String status = 'approved', DateTime? starts, DateTime? ends, String town = 'Rajahmundry', String district = 'East Godavari', String category = 'cat-1', Map<String, dynamic> more = const {}}) =>
    Entry(id, {
      'name': 'Item $id',
      'price': 30.0,
      'unit': 'per kg',
      'categoryId': category,
      'categoryName': 'Category 1',
      'locationName': town,
      'locationTown': town,
      'locationDistrict': district,
      'locationPincode': '533101',
      'status': status,
      'imageUrl': '',
      'ownerName': 'Ravi Staff',
      'ownerCode': 'ST001',
      'durationMs': 7200000,
      'startsAt': ?starts,
      'expiresAt': ?ends,
      ...more,
    });

// A vendor whose shop was locked by GPS at (17.0005, 81.804) in Rajahmundry.
const _vendor = Entry('v1', {
  'role': 'vendor', 'code': 'VN001', 'name': 'Ramu', 'active': true, 'shopLocked': true,
  'locationTown': 'Rajahmundry', 'locationDistrict': 'East Godavari', 'locationPincode': '533101',
  'shopLatitude': 17.0005, 'shopLongitude': 81.804,
});
const _newVendor = Entry('v2', {'role': 'vendor', 'code': 'VN002', 'name': 'New', 'active': true, 'shopLocked': false});
const _staff = Entry('s1', {'role': 'staff', 'code': 'ST001', 'name': 'Ravi', 'active': true});

const _atShop = QuickFix(17.0006, 81.804); // about 11 m from the shop
const _awayFromShop = QuickFix(17.003, 81.804); // about 280 m from the shop

Place _place(String town, String district, String pincode) =>
    Place(name: town, district: district, state: 'Andhra Pradesh', pincode: pincode, village: false, latitude: 17, longitude: 81.8, town: town);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

QuickPhotoResult _photoResult([String id = 'photo-1']) => QuickPhotoResult(id, Uint8List.fromList(_tinyPng));

void main() {
  group('timing rules', () {
    test('phases follow the clock: pending, scheduled, live, expired', () {
      final start = _now.add(const Duration(hours: 1)), end = _now.add(const Duration(hours: 3));
      expect(quickPhase(_item('a', status: 'pending'), _now), QuickPhase.pending);
      expect(quickPhase(_item('a', starts: start, ends: end), _now), QuickPhase.scheduled);
      expect(quickPhase(_item('a', starts: start, ends: end), start), QuickPhase.live);
      expect(quickPhase(_item('a', starts: start, ends: end), end.subtract(const Duration(seconds: 1))), QuickPhase.live);
      expect(quickPhase(_item('a', starts: start, ends: end), end), QuickPhase.expired);
      expect(quickPhase(_item('a', status: 'expired'), _now), QuickPhase.expired);
      expect(quickPhase(_item('a', status: 'rejected'), _now), QuickPhase.rejected);
      expect(quickPhase(_item('a', status: 'cancelled'), _now), QuickPhase.cancelled);
    });

    test('My Items tabs: Scheduled, Live, Expired', () {
      expect(quickTabOf(QuickPhase.pending), QuickTab.scheduled);
      expect(quickTabOf(QuickPhase.scheduled), QuickTab.scheduled);
      expect(quickTabOf(QuickPhase.live), QuickTab.live);
      for (final p in [QuickPhase.expired, QuickPhase.rejected, QuickPhase.cancelled]) {
        expect(quickTabOf(p), QuickTab.expired);
      }
    });

    test('countdown reads like 2h 15m', () {
      expect(quickCountdown(const Duration(hours: 2, minutes: 15)), '2h 15m');
      expect(quickCountdown(const Duration(hours: 2)), '2h');
      expect(quickCountdown(const Duration(minutes: 45)), '45m');
      expect(quickCountdown(const Duration(days: 1, hours: 3, minutes: 5)), '1d 3h');
      expect(quickCountdown(const Duration(seconds: 20)), '<1m');
      expect(quickCountdown(const Duration(seconds: -5)), '<1m');
    });

    test('customers get only live items of their own town and category, soonest-ending first', () {
      final live = _now.subtract(const Duration(minutes: 10));
      final items = [
        _item('later', starts: live, ends: _now.add(const Duration(hours: 5))),
        _item('soon', starts: live, ends: _now.add(const Duration(hours: 1))),
        _item('over', starts: live.subtract(const Duration(hours: 5)), ends: _now.subtract(const Duration(minutes: 1))),
        _item('notYet', starts: _now.add(const Duration(hours: 1)), ends: _now.add(const Duration(hours: 4))),
        _item('pending', status: 'pending'),
        _item('rejected', status: 'rejected'),
        _item('elsewhere', town: 'Kakinada', starts: live, ends: _now.add(const Duration(hours: 2))),
        _item('otherCat', category: 'cat-9', starts: live, ends: _now.add(const Duration(hours: 2))),
      ];
      List<String> ids(Iterable<Entry> list) => [for (final i in list) i.id];
      expect(ids(liveQuickItems(items, _now, town: 'Rajahmundry', district: 'East Godavari')), ['soon', 'otherCat', 'later']);
      expect(ids(liveQuickItems(items, _now, town: 'Rajahmundry', categoryId: 'cat-1')), ['soon', 'later']);
      expect(ids(liveQuickItems(items, _now, town: 'Kakinada')), ['elsewhere']);
      expect(liveQuickItems(items, _now, town: ''), isEmpty, reason: 'no town chosen: nothing');
    });

    test('town matching ignores case and spacing, and keeps same-named towns of different districts apart', () {
      final item = _item('a', town: 'Rajahmundry', district: 'East Godavari');
      expect(quickItemAtPlace(item, town: ' rajahmundry '), isTrue);
      expect(quickItemAtPlace(item, town: 'Rajahmundry', district: 'east  godavari'), isTrue);
      expect(quickItemAtPlace(item, town: 'Rajahmundry', district: 'Krishna'), isFalse);
      expect(quickItemAtPlace(item, town: 'Kakinada'), isFalse);
      // an item from an extra place the admin added has only a name
      expect(quickItemAtPlace(const Entry('x', {'locationName': 'Old Market'}), town: 'Old Market'), isTrue);
    });
  });

  group('the pincode directory gives every place a coordinate', () {
    test('rows without coordinates get a neighbour estimate (the same numbers as the server)', () {
      final filled = filledCoordinates(realIndexJson['places'] as List);
      expect(filled.length, (realIndexJson['places'] as List).length);
      expect(filled.where((c) => c.$1 == 0 && c.$2 == 0), isEmpty, reason: 'no place is left without a location');
      expect(filled[1], (14.352, 77.348)); // Achampalle -- same as functions/places.js
      expect(filled[2], (14.085, 77.437)); // Adadakulapalli
      expect(filled[3], (13.805, 77.044)); // Agali S.O
    });

    test('the nearest town to a GPS fix is found, and nothing outside Andhra Pradesh and Telangana', () {
      expect(realIndex.nearestTown(17.0005, 81.804)?.town, 'Rajahmundry');
      expect(realIndex.nearestTown(13.0, 77.5), isNull, reason: 'Bengaluru');
    });
  });

  group('form checks', () {
    test('every missing piece is named', () {
      final errors = quickItemErrors(name: '', rate: '', unit: null, hasPhoto: false, needsLocation: true, locationId: null, timing: QuickTiming(startMode: 'schedule'), now: _now);
      expect(errors.length, 6);
      expect(errors, containsAll(['Take or choose a photo of the item.', 'Enter the item name.', 'Enter the rate above 0.', 'Choose the location.', 'Pick the date and time to start.']));
      expect(quickItemErrors(name: 'Tomato', rate: '30', unit: 'per kg', hasPhoto: true, needsLocation: false, locationId: null, timing: QuickTiming(), now: _now), isEmpty);
      expect(quickItemErrors(name: 'Tomato', rate: '0', unit: 'per kg', hasPhoto: true, needsLocation: false, locationId: null, timing: QuickTiming(), now: _now), ['Enter the rate above 0.']);
      expect(
        quickItemErrors(name: 'Tomato', rate: '30', unit: 'per kg', hasPhoto: true, needsLocation: false, locationId: null, timing: QuickTiming(startMode: 'schedule', scheduleAt: _now.subtract(const Duration(hours: 1))), now: _now),
        ['The start time must be in the future.'],
      );
    });

    test('the admin search finds a person by their Quick Add code', () {
      expect(adminSearchMatches('ST005', 'Ravi', 'ST005', 'uid1'), isTrue);
      expect(adminSearchMatches('st005', 'Ravi', 'ST005', 'uid1'), isTrue);
      expect(adminSearchMatches('VN012', 'Ramu', 'VN012', 'uid2'), isTrue);
      expect(adminSearchMatches('ST006', 'Ravi', 'ST005', 'uid1'), isFalse);
    });

    test('the distance from the shop is measured in metres', () {
      expect(quickMetresFromShop(_vendor, _atShop)!, lessThan(quickShopRadiusMetres));
      expect(quickMetresFromShop(_vendor, _awayFromShop)!, greaterThan(quickShopRadiusMetres));
      expect(quickMetresFromShop(_newVendor, _atShop), isNull, reason: 'no shop location yet');
    });
  });

  group('daily limit display', () {
    test('the day is the Indian calendar day, like on the server', () {
      expect(quickDayKey(DateTime.utc(2026, 10, 21, 18, 29)), '2026-10-21');
      expect(quickDayKey(DateTime.utc(2026, 10, 21, 18, 31)), '2026-10-22');
    });

    test('the limit is the admin setting, else 15 for staff and 6 for vendors', () {
      expect(quickDailyLimit('staff', const Entry('business', {})), 15);
      expect(quickDailyLimit('vendor', const Entry('business', {})), 6);
      expect(quickDailyLimit('staff', const Entry('business', {'quickItemsPerDayStaff': 20})), 20);
      expect(quickDailyLimit('vendor', const Entry('business', {'quickItemsPerDayVendor': 0})), 6);
    });

    testWidgets('the panel shows how many items were added today and stops at the limit', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _vendor, usedToday: 2, dailyLimit: 6))));
      expect(find.text('Today: 2 of 6 items added.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('quick-add-button'))).onPressed, isNotNull);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _vendor, usedToday: 6, dailyLimit: 6))));
      expect(find.text('Daily limit reached: 6 of 6 items today.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('quick-add-button'))).onPressed, isNull);
      expect(find.byKey(const ValueKey('quick-my-items-button')), findsOneWidget, reason: 'My Items stays available');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _vendor))));
      expect(find.byKey(const ValueKey('quick-today')), findsNothing, reason: 'nothing while the count is loading');
    });
  });

  group('vendor: the shop is set once by GPS and locked', () {
    testWidgets('before it is set only the setup button shows; after, Add items and My Items', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _newVendor))));
      expect(find.byKey(const ValueKey('quick-shop-setup')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-button')), findsNothing);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _vendor))));
      expect(find.byKey(const ValueKey('quick-shop-setup')), findsNothing);
      expect(find.byKey(const ValueKey('quick-add-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-my-items-button')), findsOneWidget);
      expect(find.textContaining('Rajahmundry, East Godavari • 533101 (locked)'), findsOneWidget);
    });

    testWidgets('GPS finds the nearest town and pincode, then Save and lock sends the GPS fix', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      Map<String, dynamic>? sent;
      final env = QuickEnv(
        locate: () async => _atShop,
        findPlace: (lat, lng) async => _place('Rajahmundry', 'East Godavari', '533101'),
        call: (name, data) async {
          calls.add(name);
          sent = data;
          return {};
        },
      );
      await tester.pumpWidget(MaterialApp(home: QuickShopSetupPage(store: store, account: _newVendor, env: env)));
      expect(find.byKey(const ValueKey('quick-lock-shop')), findsNothing, reason: 'nothing to lock before the GPS reading');
      await tester.tap(find.byKey(const ValueKey('quick-find-shop')));
      await tester.pumpAndSettle();
      expect(find.text('Rajahmundry, East Godavari'), findsOneWidget);
      expect(find.text('Andhra Pradesh • Pincode 533101'), findsOneWidget);
      expect(find.textContaining('locked'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('quick-lock-shop')));
      await tester.pumpAndSettle();
      expect(calls, ['setQuickShopLocation']);
      expect(sent, {'latitude': 17.0006, 'longitude': 81.804});
    });

    testWidgets('outside Andhra Pradesh / Telangana, or with GPS off, there is a clear message and no lock button', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(
        home: QuickShopSetupPage(store: store, account: _newVendor, env: QuickEnv(locate: () async => const QuickFix(13.0, 77.5), findPlace: (a, b) async => null)),
      ));
      await tester.tap(find.byKey(const ValueKey('quick-find-shop')));
      await tester.pumpAndSettle();
      expect(find.textContaining('outside Andhra Pradesh and Telangana'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-lock-shop')), findsNothing);
      await tester.pumpWidget(MaterialApp(
        home: QuickShopSetupPage(store: store, account: _newVendor, env: QuickEnv(locate: () async => throw StateError('Turn on location services on this device, then try again.'))),
      ));
      await tester.tap(find.byKey(const ValueKey('quick-find-shop')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Turn on location services'), findsOneWidget);
    });

    testWidgets('a vendor sees up to 5 item rows, each with its own photo, name, rate and unit', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: QuickBatchFormPage(store: store, account: _vendor, category: const Entry('cat-0', {'name': 'Vegetables'}))));
      expect(find.byKey(const ValueKey('quick-row-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-location-fixed')), findsOneWidget);
      for (var i = 1; i < 5; i++) {
        await _tap(tester, find.byKey(const ValueKey('quick-row-add')));
      }
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('quick-row-$i'), skipOffstage: false), findsOneWidget);
        expect(find.byKey(ValueKey('quick-camera-$i'), skipOffstage: false), findsOneWidget);
        expect(find.byKey(ValueKey('quick-gallery-$i'), skipOffstage: false), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('quick-row-add')), findsNothing, reason: 'five is the most');
      await _tap(tester, find.byKey(const ValueKey('quick-row-remove-4')));
      expect(find.byKey(const ValueKey('quick-row-4'), skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('quick-row-add'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('at the shop (within 100 m): all rows are saved in one go, with the GPS fix', (tester) async {
      _phone(tester);
      final store = await _store();
      Map<String, dynamic>? sent;
      var n = 0;
      final env = QuickEnv(
        locate: () async => _atShop,
        pick: (source) async => _photoResult('p${++n}'),
        call: (name, data) async {
          expect(name, 'saveQuickItems');
          sent = data;
          return {'status': 'pending'};
        },
      );
      await tester.pumpWidget(MaterialApp(home: QuickBatchFormPage(store: store, account: _vendor, category: const Entry('cat-0', {'name': 'Vegetables'}), env: env)));
      await _tap(tester, find.byKey(const ValueKey('quick-row-add')));
      Future<void> fill(int i, String name, String rate, String unit) async {
        await _tap(tester, find.byKey(ValueKey('quick-gallery-$i')));
        await tester.enterText(find.byKey(ValueKey('quick-name-$i')), name);
        await tester.enterText(find.byKey(ValueKey('quick-rate-$i')), rate);
        await tester.ensureVisible(find.byKey(ValueKey('quick-unit-$i')));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('quick-unit-$i')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(unit).last);
        await tester.pumpAndSettle();
      }

      await fill(0, 'Tomatoes', '30', 'per kg');
      await fill(1, 'Mangoes', '90', 'per dozen');
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!['categoryId'], 'cat-0');
      expect(sent!['latitude'], 17.0006);
      expect(sent!['longitude'], 81.804);
      expect(sent!['items'], [
        {'submissionId': 'p1', 'name': 'Tomatoes', 'price': 30.0, 'unit': 'per kg'},
        {'submissionId': 'p2', 'name': 'Mangoes', 'price': 90.0, 'unit': 'per dozen'},
      ]);
      expect(sent!.containsKey('locationTown'), isFalse, reason: 'the vendor never sends a place');
      expect(find.text('Add more items'), findsOneWidget);
    });

    testWidgets('away from the shop (over 100 m): nothing is sent and the message says so', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      final env = QuickEnv(
        locate: () async => _awayFromShop,
        pick: (source) async => _photoResult(),
        call: (name, data) async {
          calls.add(name);
          return {};
        },
      );
      await tester.pumpWidget(MaterialApp(home: QuickBatchFormPage(store: store, account: _vendor, category: const Entry('cat-0', {'name': 'Vegetables'}), env: env)));
      await _tap(tester, find.byKey(const ValueKey('quick-gallery-0')));
      await tester.enterText(find.byKey(const ValueKey('quick-name-0')), 'Tomatoes');
      await tester.enterText(find.byKey(const ValueKey('quick-rate-0')), '30');
      await tester.ensureVisible(find.byKey(const ValueKey('quick-unit-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick-unit-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per kg').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(quickNotAtShop, skipOffstage: false), findsWidgets);
      expect(find.textContaining('మీరు మీ షాప్ దగ్గర లేరు', skipOffstage: false), findsWidgets);
    });

    testWidgets('each row must be complete; the problems say which item', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: QuickBatchFormPage(store: store, account: _vendor, category: const Entry('cat-0', {'name': 'Vegetables'}), env: QuickEnv(locate: () async => _atShop, call: (n, d) async { calls.add(n); return {}; })),
      ));
      await _tap(tester, find.byKey(const ValueKey('quick-row-add')));
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      expect(calls, isEmpty);
      expect(find.text('• Item 1: Take or choose a photo of the item.', skipOffstage: false), findsOneWidget);
      expect(find.text('• Item 2: Enter the item name.', skipOffstage: false), findsOneWidget);
    });

    testWidgets('editing an item also needs the vendor to be at the shop', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      var fix = _awayFromShop;
      final env = QuickEnv(locate: () async => fix, call: (n, d) async { calls.add(n); return {}; });
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(store: store, account: _vendor, category: const Entry('cat-1', {'name': 'Category 1'}), editing: _item('e1', status: 'rejected', more: {'unit': 'per kg'}), env: env),
      ));
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.textContaining('మీరు మీ షాప్ దగ్గర లేరు', skipOffstage: false), findsWidgets);
      fix = _atShop;
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(calls, ['saveQuickItem']);
    });
  });

  group('staff phone screens', () {
    testWidgets('all 24 categories are big buttons', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: QuickCategoryPage(store: store, account: _staff)));
      for (var i = 0; i < 24; i++) {
        expect(find.byKey(ValueKey('quick-category-cat-$i'), skipOffstage: false), findsOneWidget);
      }
    });

    testWidgets('an inactive account sees the message and no Add button', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: const Entry('s1', {'role': 'staff', 'code': 'ST002', 'name': 'Sita', 'active': false})))));
      expect(find.text('Your account is inactive, contact admin.'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-button')), findsNothing);
      expect(find.byKey(const ValueKey('quick-my-items-button')), findsNothing);
    });

    testWidgets('taking the photo reads GPS and selects the nearest town and pincode; the payload carries them', (tester) async {
      _phone(tester);
      final store = await _store();
      final sources = <ImageSource>[];
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(
          store: store,
          account: _staff,
          category: const Entry('cat-0', {'name': 'Fruits'}),
          env: QuickEnv(
            locate: () async => const QuickFix(17.0005, 81.804),
            findPlace: (lat, lng) async => _place('Rajahmundry', 'East Godavari', '533101'),
            pick: (source) async {
              sources.add(source);
              return _photoResult();
            },
            call: (name, data) async {
              sent = data;
              return {'status': 'pending'};
            },
          ),
        ),
      ));
      // nothing filled in: every problem is listed and nothing is sent
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      expect(find.byKey(const ValueKey('quick-error'), skipOffstage: false), findsOneWidget);
      expect(find.text('• Take or choose a photo of the item.', skipOffstage: false), findsOneWidget);
      expect(find.text('• Choose the location.', skipOffstage: false), findsOneWidget);
      expect(sent, isNull);
      expect(find.text('Town not found yet'), findsOneWidget);
      // the photo is taken -> the town is found from GPS
      await _tap(tester, find.byKey(const ValueKey('quick-camera')));
      await tester.pumpAndSettle();
      expect(sources, [ImageSource.camera]);
      expect(find.byKey(const ValueKey('quick-photo-preview')), findsOneWidget);
      expect(find.text('Rajahmundry, East Godavari'), findsOneWidget);
      expect(find.text('Pincode 533101 • from your location'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('quick-name')), 'Bananas');
      await tester.enterText(find.byKey(const ValueKey('quick-rate')), '45');
      await tester.tap(find.byKey(const ValueKey('quick-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per piece').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-duration-3')));
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(sent, {
        'submissionId': 'photo-1',
        'name': 'Bananas',
        'categoryId': 'cat-0',
        'price': 45.0,
        'unit': 'per piece',
        'locationTown': 'Rajahmundry',
        'locationDistrict': 'East Godavari',
        'locationPincode': '533101',
        'latitude': 17.0005,
        'longitude': 81.804,
        'startMode': 'now',
        'durationUnit': 'hours',
        'durationValue': 3,
      });
      expect(find.text('Add next item'), findsOneWidget);
    });

    testWidgets('staff can search another town from the directory and it is kept even after more photos', (tester) async {
      _phone(tester);
      final store = await _store();
      usePlacesFixture();
      Map<String, dynamic>? sent;
      final kakinada = realIndex.search('Kakinada', limit: 1).first;
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(
          store: store,
          account: _staff,
          category: const Entry('cat-0', {'name': 'Fruits'}),
          env: QuickEnv(
            locate: () async => const QuickFix(17.0005, 81.804),
            findPlace: (lat, lng) async => _place('Rajahmundry', 'East Godavari', '533101'),
            loadPlaces: () async => realIndex,
            pick: (source) async => _photoResult(),
            call: (name, data) async {
              sent = data;
              return {};
            },
          ),
        ),
      ));
      await _tap(tester, find.byKey(const ValueKey('quick-gallery')));
      await tester.pumpAndSettle();
      expect(find.text('Rajahmundry, East Godavari'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-place-change')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quick-place-search')), 'Kakinada');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('quick-place-${kakinada.pincode}-${kakinada.name}')));
      await tester.pumpAndSettle();
      expect(find.text(kakinada.label), findsOneWidget);
      expect(find.text('Pincode ${kakinada.pincode}'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-gallery'))); // another photo: GPS must not undo their choice
      await tester.pumpAndSettle();
      expect(find.text(kakinada.label), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('quick-name')), 'Bananas');
      await tester.enterText(find.byKey(const ValueKey('quick-rate')), '45');
      await tester.tap(find.byKey(const ValueKey('quick-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per kg').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(sent!['locationTown'], kakinada.town);
      expect(sent!['locationDistrict'], kakinada.district);
      expect(sent!['locationPincode'], kakinada.pincode);
    });

    testWidgets('with GPS off the town is chosen by hand, and an extra place the admin added can be used', (tester) async {
      _phone(tester);
      final store = await _store(extraPlace: true);
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(
          store: store,
          account: _staff,
          category: const Entry('cat-0', {'name': 'Fruits'}),
          env: QuickEnv(
            locate: () async => throw StateError('no gps'),
            loadPlaces: () async => realIndex,
            pick: (source) async => _photoResult(),
            call: (name, data) async {
              sent = data;
              return {};
            },
          ),
        ),
      ));
      await _tap(tester, find.byKey(const ValueKey('quick-gallery')));
      await tester.pumpAndSettle();
      expect(find.text('Town not found yet'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-place-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-extra-loc-mkt')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-extra-loc-off')), findsNothing, reason: 'inactive extras are not offered');
      await tester.tap(find.byKey(const ValueKey('quick-extra-loc-mkt')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quick-name')), 'Bananas');
      await tester.enterText(find.byKey(const ValueKey('quick-rate')), '45');
      await tester.tap(find.byKey(const ValueKey('quick-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per kg').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(sent!['locationId'], 'loc-mkt');
      expect(sent!.containsKey('locationTown'), isFalse);
    });

    testWidgets('Schedule asks for a date and time; hours and days offer 1-4 and 1-3', (tester) async {
      _phone(tester);
      final timing = QuickTiming();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickTimingFields(timing: timing)))));
      expect(find.byKey(const ValueKey('quick-pick-schedule')), findsNothing, reason: 'Now: no date picker');
      for (final h in [1, 2, 3, 4]) {
        expect(find.byKey(ValueKey('quick-duration-$h')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('quick-duration-5')), findsNothing);
      await tester.tap(find.text('Schedule'));
      await tester.pump();
      expect(timing.startMode, 'schedule');
      expect(find.byKey(const ValueKey('quick-pick-schedule')), findsOneWidget);
      expect(find.text('Pick date and time'), findsOneWidget);
      await tester.tap(find.text('Days'));
      await tester.pump();
      expect(timing.durationUnit, 'days');
      for (final d in [1, 2, 3]) {
        expect(find.byKey(ValueKey('quick-duration-$d')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('quick-duration-4')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quick-duration-3')));
      await tester.pump();
      expect(timing.toPayload(), {'startMode': 'schedule', 'durationUnit': 'days', 'durationValue': 3});
    });

    testWidgets('My Items: items land in Scheduled / Live / Expired with the right buttons', (tester) async {
      _phone(tester);
      final store = await _store();
      final real = DateTime.now();
      final calls = <String>[];
      final items = [
        _item('wait', status: 'pending'),
        _item('later', starts: real.add(const Duration(hours: 5)), ends: real.add(const Duration(hours: 7))),
        _item('now', starts: real.subtract(const Duration(minutes: 5)), ends: real.add(const Duration(hours: 2, minutes: 20))),
        _item('done', starts: real.subtract(const Duration(hours: 5)), ends: real.subtract(const Duration(hours: 1))),
        _item('no', status: 'rejected', more: {'decisionReason': 'blurry'}),
        _item('stopped', status: 'cancelled'),
      ];
      await tester.pumpWidget(MaterialApp(
        home: QuickMyItemsPage(
          store: store,
          account: _staff,
          stream: Stream.value(items),
          env: QuickEnv(call: (name, data) async {
            calls.add('$name:${data['itemId']}');
            return {};
          }),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-item-wait')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-item-later')), findsOneWidget);
      expect(find.text('Waiting for admin approval'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-item-now')), findsNothing);
      expect(find.byKey(const ValueKey('quick-cancel-wait')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-edit-wait')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-cancel-wait')));
      await tester.pump();
      expect(calls, ['cancelQuickItem:wait']);
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-item-now')), findsOneWidget);
      expect(find.textContaining('Available for 2h'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-reactivate-now')), findsNothing);
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      for (final id in ['done', 'no', 'stopped']) {
        expect(find.byKey(ValueKey('quick-reactivate-$id')), findsOneWidget, reason: id);
        expect(find.byKey(ValueKey('quick-cancel-$id')), findsNothing, reason: id);
      }
      expect(find.text('Rejected: blurry'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-confirm')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reactivateQuickItem:done');
    });

    testWidgets('a vendor re-activating an item must be at the shop', (tester) async {
      _phone(tester);
      final store = await _store();
      final real = DateTime.now();
      final calls = <Map<String, dynamic>>[];
      var fix = _awayFromShop;
      await tester.pumpWidget(MaterialApp(
        home: QuickMyItemsPage(
          store: store,
          account: _vendor,
          stream: Stream.value([_item('done', starts: real.subtract(const Duration(hours: 5)), ends: real.subtract(const Duration(hours: 1)))]),
          env: QuickEnv(locate: () async => fix, call: (name, data) async {
            calls.add({'name': name, ...data});
            return {};
          }),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-confirm')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(quickNotAtShop), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      fix = _atShop;
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-confirm')));
      await tester.pumpAndSettle();
      expect(calls.single['name'], 'reactivateQuickItem');
      expect(calls.single['latitude'], 17.0006);
    });
  });

  group('admin screens', () {
    testWidgets('the list shows code, role, town and Inactive; Add opens the form', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(
        home: QuickAccountsPage(
          store: store,
          stream: Stream.value(const [
            Entry('s1', {'role': 'staff', 'code': 'ST001', 'name': 'Ravi', 'active': true}),
            Entry('v1', {'role': 'vendor', 'code': 'VN001', 'name': 'Ramu', 'locationName': 'Rajahmundry', 'active': false}),
          ]),
        ),
      ));
      await tester.pump();
      expect(find.text('Ravi  •  ST001'), findsOneWidget);
      expect(find.text('Vendor • Rajahmundry • INACTIVE'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-account-add')));
      await tester.pumpAndSettle();
      expect(find.text('Add Staff / Vendor'), findsWidgets);
    });

    testWidgets('creating a vendor needs name, phone, email and photo only -- no location is typed in', (tester) async {
      _phone(tester);
      final store = await _store();
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: QuickAccountForm(
          store: store,
          pickPhoto: () async => 'https://example.test/p.jpg',
          call: (name, data) async {
            sent = {'function': name, ...data};
            return {'code': 'VN001', 'resetLink': 'https://reset.example/abc', 'uid': 'u'};
          },
        ),
      ));
      await tester.tap(find.text('Vendor (VN...)'));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-account-location')), findsNothing, reason: 'the vendor sets the shop by GPS');
      expect(find.byKey(const ValueKey('quick-account-location-note'), skipOffstage: false), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-account-create')));
      expect(sent, isNull);
      expect(find.textContaining('Enter the name'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-account-photo')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('quick-account-name')), 'Ramu Fresh');
      await tester.enterText(find.byKey(const ValueKey('quick-account-phone')), '9876543210');
      await tester.enterText(find.byKey(const ValueKey('quick-account-email')), 'ramu@example.test');
      await _tap(tester, find.byKey(const ValueKey('quick-account-create')));
      await tester.pumpAndSettle();
      expect(sent, {
        'function': 'createQuickAccount',
        'role': 'vendor',
        'name': 'Ramu Fresh',
        'phone': '9876543210',
        'email': 'ramu@example.test',
        'photoUrl': 'https://example.test/p.jpg',
      });
      expect(find.text('Created: VN001'), findsOneWidget);
      expect(find.text('https://reset.example/abc'), findsOneWidget);
    });

    testWidgets('details page: name, code, phone, locked town, Active switch, Unlock and pending items with Approve / Reject', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: QuickAccountDetailPage(
          store: store,
          uid: 'v1',
          accountStream: Stream.value(const Entry('v1', {
            'role': 'vendor', 'code': 'VN012', 'name': 'Ramu', 'phone': '9876543210', 'email': 'r@e.test', 'photoUrl': '', 'active': true,
            'shopLocked': true, 'locationTown': 'Rajahmundry', 'locationDistrict': 'East Godavari', 'locationPincode': '533101',
          })),
          itemsStream: Stream.value([_item('p1', status: 'pending'), _item('p2', status: 'pending'), _item('old', status: 'rejected')]),
          call: (name, data) async {
            calls.add('$name:${data['active'] ?? data['itemIds'] ?? data['resetShopLocation']}:${data['approved'] ?? ''}');
            return {};
          },
        ),
      ));
      await tester.pump();
      expect(find.text('Ramu'), findsOneWidget);
      expect(find.text('VN012 • Vendor'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Rajahmundry, East Godavari • 533101'), findsOneWidget);
      expect(find.text('Pending items (2)'), findsOneWidget);
      expect(find.text('Added by: Ravi Staff (ST001)'), findsWidgets);
      // Unlock the shop location
      await _tap(tester, find.byKey(const ValueKey('quick-unlock-shop')));
      await tester.pumpAndSettle();
      expect(calls.last, 'updateQuickAccount:true:');
      // Active switch
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('quick-active-switch'))).value, isTrue);
      await _tap(tester, find.byKey(const ValueKey('quick-active-switch')));
      await tester.pumpAndSettle();
      expect(calls.last, 'setQuickAccountActive:false:');
      await _tap(tester, find.byKey(const ValueKey('quick-approve-p1')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reviewQuickItems:[p1]:true');
      await _tap(tester, find.byKey(const ValueKey('quick-approve-all')));
      await tester.pumpAndSettle();
      expect(calls.last, anyOf('reviewQuickItems:[p1, p2]:true', 'reviewQuickItems:[p2, p1]:true'));
      await _tap(tester, find.byKey(const ValueKey('quick-reject-p2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quick-reject-reason')), 'wrong price');
      await tester.tap(find.byKey(const ValueKey('quick-reject-confirm')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reviewQuickItems:[p2]:false');
    });

    testWidgets('a vendor who has not set the shop yet says so, with no Unlock button', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(
        home: QuickAccountDetailPage(
          store: store,
          uid: 'v2',
          accountStream: Stream.value(const Entry('v2', {'role': 'vendor', 'code': 'VN002', 'name': 'New', 'active': true, 'shopLocked': false})),
          itemsStream: Stream.value(const []),
        ),
      ));
      await tester.pump();
      expect(find.text('Shop location not set yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-unlock-shop')), findsNothing);
    });

    testWidgets('all items page: shows who added each item, the town and pincode; filters; Approve all', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <List<Object?>>[];
      final live = DateTime.now().subtract(const Duration(minutes: 5));
      await tester.pumpWidget(MaterialApp(
        home: QuickItemsAdminPage(
          store: store,
          stream: Stream.value([
            _item('p1', status: 'pending'),
            _item('p2', status: 'pending', town: 'Kakinada', more: {'ownerName': 'Sita Staff', 'ownerCode': 'ST002', 'locationPincode': '533001'}),
            _item('l1', starts: live, ends: live.add(const Duration(hours: 2))),
          ]),
          call: (name, data) async {
            calls.add(data['itemIds'] as List<Object?>);
            return {};
          },
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-review-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-l1')), findsNothing, reason: 'pending filter first');
      expect(find.text('Added by: Sita Staff (ST002)'), findsOneWidget);
      expect(find.text('Location: Kakinada'), findsOneWidget);
      expect(find.text('Pincode: 533001'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-approve-all-pending')));
      await tester.pumpAndSettle();
      expect(calls.single.toSet(), {'p1', 'p2'});
      await _tap(tester, find.byKey(const ValueKey('quick-filter-live')));
      expect(find.byKey(const ValueKey('quick-review-l1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-p1')), findsNothing);
      expect(find.byKey(const ValueKey('quick-reject-l1')), findsOneWidget, reason: 'a live item can be taken down');
      await _tap(tester, find.byKey(const ValueKey('quick-filter-all')));
      expect(find.byKey(const ValueKey('quick-review-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-l1')), findsOneWidget);
    });
  });

  group('customer website', () {
    Future<Store> chosenTown({String town = 'Rajahmundry', String district = 'East Godavari'}) async {
      final store = await _store();
      store.town = town;
      store.district = district;
      return store;
    }

    final liveFrom = _now.subtract(const Duration(minutes: 5));

    testWidgets('shows "Showing items in" the customer\'s own town, the live items with a countdown, and hides finished ones', (tester) async {
      _phone(tester);
      final store = await chosenTown();
      store.catalog['quickItems'] = [
        _item('tom', starts: liveFrom, ends: _now.add(const Duration(hours: 2, minutes: 15)), more: {'name': 'Tomatoes'}),
        _item('over', starts: _now.subtract(const Duration(hours: 5)), ends: _now.subtract(const Duration(minutes: 1)), more: {'name': 'Gone Beans'}),
        _item('kak', town: 'Kakinada', starts: liveFrom, ends: _now.add(const Duration(hours: 1)), more: {'name': 'Kakinada Mangoes'}),
        _item('wait', status: 'pending', more: {'name': 'Pending Peas'}),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now)))));
      await tester.pump();
      expect(find.text('Showing items in: Rajahmundry'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Fresh today'), findsOneWidget);
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Available for 2h 15m'), findsOneWidget);
      expect(find.text('₹30 per kg'), findsOneWidget);
      expect(find.text('Gone Beans'), findsNothing);
      expect(find.text('Kakinada Mangoes'), findsNothing, reason: 'another town\'s item');
      expect(find.text('Pending Peas'), findsNothing);
    });

    testWidgets('the same item disappears once its time is up', (tester) async {
      _phone(tester);
      final store = await chosenTown();
      store.catalog['quickItems'] = [
        _item('tom', starts: liveFrom, ends: _now.add(const Duration(minutes: 30)), more: {'name': 'Tomatoes'}),
      ];
      var clock = _now;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => clock)))));
      await tester.pump();
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Available for 30m'), findsOneWidget);
      clock = _now.add(const Duration(minutes: 31));
      await tester.pump(const Duration(seconds: 31)); // the strip re-checks every 30 s
      expect(find.text('Tomatoes'), findsNothing);
    });

    testWidgets('Change uses the normal "Choose your location" and the items follow the new town', (tester) async {
      _phone(tester);
      final store = await chosenTown();
      store.catalog['quickItems'] = [
        _item('tom', starts: liveFrom, ends: _now.add(const Duration(hours: 2)), more: {'name': 'Tomatoes'}),
        _item('kak', town: 'Kakinada', starts: liveFrom, ends: _now.add(const Duration(hours: 1)), more: {'name': 'Kakinada Mangoes'}),
      ];
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickFreshToday(
              store: store,
              now: () => _now,
              choose: (context, s) async {
                opened++;
                await s.setLocation('533001', 'Kakinada', town: 'Kakinada', district: 'East Godavari', state: 'Andhra Pradesh');
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Kakinada Mangoes'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quick-change-location')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('Showing items in: Kakinada'), findsOneWidget);
      expect(find.text('Kakinada Mangoes'), findsOneWidget);
      expect(find.text('Tomatoes'), findsNothing);
    });

    testWidgets('no town chosen yet: asked to choose, and no items are shown', (tester) async {
      _phone(tester);
      final store = await _store();
      store.catalog['quickItems'] = [_item('tom', starts: liveFrom, ends: _now.add(const Duration(hours: 2)), more: {'name': 'Tomatoes'})];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now)))));
      await tester.pump();
      expect(find.text('Choose your location to see fresh items'), findsOneWidget);
      expect(find.text('Choose'), findsOneWidget);
      expect(find.text('Tomatoes'), findsNothing);
    });

    testWidgets('a town with nothing live says so; and nothing shows at all while no item is approved', (tester) async {
      _phone(tester);
      final store = await chosenTown(town: 'Warangal', district: 'Warangal Urban');
      store.catalog['quickItems'] = [_item('tom', starts: liveFrom, ends: _now.add(const Duration(hours: 2)))];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now)))));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-none-here')), findsOneWidget);
      final empty = await chosenTown();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: empty)))));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-showing-in')), findsNothing);
    });

    testWidgets('a category page lists its live quick items for the customer\'s town', (tester) async {
      _phone(tester);
      final store = await chosenTown();
      store.catalog['quickItems'] = [
        _item('tom', category: 'cat-1', starts: liveFrom, ends: _now.add(const Duration(hours: 2)), more: {'name': 'Tomatoes'}),
        _item('shirt', category: 'cat-9', starts: liveFrom, ends: _now.add(const Duration(hours: 2)), more: {'name': 'Shirts'}),
        _item('kak', category: 'cat-1', town: 'Kakinada', starts: liveFrom, ends: _now.add(const Duration(hours: 2)), more: {'name': 'Kakinada Mangoes'}),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickCategoryItems(store: store, categoryId: 'cat-1', now: () => _now)))));
      await tester.pump();
      expect(find.text('Fresh today in Rajahmundry'), findsOneWidget);
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Shirts'), findsNothing);
      expect(find.text('Kakinada Mangoes'), findsNothing);
    });
  });
}

// A 1x1 transparent PNG, enough for the photo preview.
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
