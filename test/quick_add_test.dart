import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/quick_items.dart';
import 'package:ecommerce_app/ui/admin_search.dart';
import 'package:ecommerce_app/ui/quick_add.dart';
import 'package:ecommerce_app/ui/quick_admin.dart';
import 'package:ecommerce_app/ui/quick_fresh.dart';

final _now = DateTime(2026, 10, 21, 9, 0);

Future<Store> _store({bool withLocations = true}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['categories'] = [
    for (var i = 0; i < 24; i++) Entry('cat-$i', {'name': 'Category $i', 'order': i, 'parentId': ''}),
  ];
  if (withLocations) {
    store.catalog['locations'] = const [
      Entry('loc-raj', {'name': 'Rajahmundry', 'latitude': 17.0, 'longitude': 81.8, 'order': 0}),
      Entry('loc-kak', {'name': 'Kakinada', 'latitude': 16.95, 'longitude': 82.24, 'order': 1}),
      Entry('loc-off', {'name': 'Closed', 'latitude': 10.0, 'longitude': 78.0, 'order': 2, 'active': false}),
    ];
  }
  return store;
}

Entry _item(String id, {String status = 'approved', DateTime? starts, DateTime? ends, String location = 'loc-raj', String category = 'cat-1', Map<String, dynamic> more = const {}}) =>
    Entry(id, {
      'name': 'Item $id',
      'price': 30.0,
      'unit': 'per kg',
      'categoryId': category,
      'categoryName': 'Category 1',
      'locationId': location,
      'locationName': location == 'loc-raj' ? 'Rajahmundry' : 'Kakinada',
      'status': status,
      'imageUrl': '',
      'ownerName': 'Ravi Staff',
      'ownerCode': 'ST001',
      'durationMs': 7200000,
      'startsAt': ?starts,
      'expiresAt': ?ends,
      ...more,
    });

const _vendor = Entry('v1', {'role': 'vendor', 'code': 'VN001', 'name': 'Ramu', 'locationId': 'loc-raj', 'locationName': 'Rajahmundry', 'active': true});
const _staff = Entry('s1', {'role': 'staff', 'code': 'ST001', 'name': 'Ravi', 'active': true});

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 2400);
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

    test('customers get only live items of the chosen location and category, soonest-ending first', () {
      final live = _now.subtract(const Duration(minutes: 10));
      final items = [
        _item('later', starts: live, ends: _now.add(const Duration(hours: 5))),
        _item('soon', starts: live, ends: _now.add(const Duration(hours: 1))),
        _item('over', starts: live.subtract(const Duration(hours: 5)), ends: _now.subtract(const Duration(minutes: 1))),
        _item('notYet', starts: _now.add(const Duration(hours: 1)), ends: _now.add(const Duration(hours: 4))),
        _item('pending', status: 'pending'),
        _item('rejected', status: 'rejected'),
        _item('elsewhere', location: 'loc-kak', starts: live, ends: _now.add(const Duration(hours: 2))),
        _item('otherCat', category: 'cat-9', starts: live, ends: _now.add(const Duration(hours: 2))),
      ];
      expect(liveQuickItems(items, _now, locationId: 'loc-raj').map((i) => i.id), ['soon', 'otherCat', 'later']);
      expect(liveQuickItems(items, _now, locationId: 'loc-raj', categoryId: 'cat-1').map((i) => i.id), ['soon', 'later']);
      expect(liveQuickItems(items, _now, locationId: 'loc-kak').map((i) => i.id), ['elsewhere']);
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
  });

  group('Staff and Vendor phone screens', () {
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

    testWidgets('an active account sees its code and the big buttons', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuickAddPanel(store: store, account: _vendor))));
      expect(find.text('VN001'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-my-items-button')), findsOneWidget);
    });

    testWidgets('staff pick a location from the list and a photo with Camera or Gallery; the payload carries them', (tester) async {
      _phone(tester);
      final store = await _store();
      final sources = <ImageSource>[];
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(
          store: store,
          account: _staff,
          category: const Entry('cat-0', {'name': 'Fruits'}),
          pick: (source) async {
            sources.add(source);
            return QuickPhotoResult('photo-1', Uint8List.fromList(_tinyPng));
          },
          submit: (payload) async {
            sent = payload;
            return {'status': 'pending'};
          },
        ),
      ));
      // nothing filled in: every problem is listed and nothing is sent
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      expect(find.byKey(const ValueKey('quick-error'), skipOffstage: false), findsOneWidget);
      expect(find.text('• Take or choose a photo of the item.', skipOffstage: false), findsOneWidget);
      expect(sent, isNull);
      // staff have a location dropdown, not a fixed one
      expect(find.byKey(const ValueKey('quick-location')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-location-fixed')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('quick-camera')));
      await _tap(tester, find.byKey(const ValueKey('quick-gallery')));
      expect(sources, [ImageSource.camera, ImageSource.gallery]);
      expect(find.byKey(const ValueKey('quick-photo-preview')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('quick-name')), 'Bananas');
      await tester.enterText(find.byKey(const ValueKey('quick-rate')), '45');
      await tester.tap(find.byKey(const ValueKey('quick-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per piece').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-location')));
      await tester.pumpAndSettle();
      // only active locations are offered
      expect(find.text('Closed'), findsNothing);
      await tester.tap(find.text('Kakinada').last);
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
        'locationId': 'loc-kak',
        'startMode': 'now',
        'durationUnit': 'hours',
        'durationValue': 3,
      });
      expect(find.text('Add next item'), findsOneWidget);
    });

    testWidgets('a vendor\'s location is fixed and is never sent', (tester) async {
      _phone(tester);
      final store = await _store();
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: QuickItemFormPage(
          store: store,
          account: _vendor,
          category: const Entry('cat-0', {'name': 'Vegetables'}),
          pick: (source) async => QuickPhotoResult('p', Uint8List.fromList(_tinyPng)),
          submit: (payload) async {
            sent = payload;
            return {};
          },
        ),
      ));
      expect(find.byKey(const ValueKey('quick-location')), findsNothing);
      expect(find.byKey(const ValueKey('quick-location-fixed')), findsOneWidget);
      expect(find.text('Rajahmundry'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quick-gallery')));
      await tester.enterText(find.byKey(const ValueKey('quick-name')), 'Tomatoes');
      await tester.enterText(find.byKey(const ValueKey('quick-rate')), '30');
      await tester.tap(find.byKey(const ValueKey('quick-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('per kg').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!.containsKey('locationId'), isFalse);
      expect(sent!['name'], 'Tomatoes');
    });

    testWidgets('Schedule asks for a date and time; hours and days offer 1-4 and 1-3', (tester) async {
      _phone(tester);
      final store = await _store();
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
      store.dispose();
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
          call: (name, data) async {
            calls.add('$name:${data['itemId']}');
            return {};
          },
        ),
      ));
      await tester.pump();
      // Scheduled tab: waiting for approval + scheduled for later
      expect(find.byKey(const ValueKey('quick-item-wait')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-item-later')), findsOneWidget);
      expect(find.text('Waiting for admin approval'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-item-now')), findsNothing);
      expect(find.byKey(const ValueKey('quick-cancel-wait')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-edit-wait')), findsOneWidget);
      // cancel works
      await tester.tap(find.byKey(const ValueKey('quick-cancel-wait')));
      await tester.pump();
      expect(calls, ['cancelQuickItem:wait']);
      // Live tab: countdown
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-item-now')), findsOneWidget);
      expect(find.textContaining('Available for 2h'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-reactivate-now')), findsNothing);
      // Expired tab: finished, rejected, cancelled -- each can be re-activated
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      for (final id in ['done', 'no', 'stopped']) {
        expect(find.byKey(ValueKey('quick-reactivate-$id')), findsOneWidget, reason: id);
        expect(find.byKey(ValueKey('quick-cancel-$id')), findsNothing, reason: id);
      }
      expect(find.text('Rejected: blurry'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      // re-activate asks for the timing, then sends it for approval
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reactivate-confirm')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reactivateQuickItem:done');
    });
  });

  group('admin screens', () {
    testWidgets('the list shows code, role, location and Inactive; Add opens the form', (tester) async {
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

    testWidgets('creating a vendor needs name, phone, email, photo and a location; the reset link is shown', (tester) async {
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
      await _tap(tester, find.byKey(const ValueKey('quick-account-create')));
      expect(sent, isNull);
      expect(find.textContaining('Enter the name'), findsOneWidget);
      expect(find.textContaining('shop location'), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('quick-account-photo')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('quick-account-name')), 'Ramu Fresh');
      await tester.enterText(find.byKey(const ValueKey('quick-account-phone')), '9876543210');
      await tester.enterText(find.byKey(const ValueKey('quick-account-email')), 'ramu@example.test');
      await tester.tap(find.byKey(const ValueKey('quick-account-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rajahmundry').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quick-account-create')));
      await tester.pumpAndSettle();
      expect(sent, {
        'function': 'createQuickAccount',
        'role': 'vendor',
        'name': 'Ramu Fresh',
        'phone': '9876543210',
        'email': 'ramu@example.test',
        'photoUrl': 'https://example.test/p.jpg',
        'locationId': 'loc-raj',
      });
      expect(find.text('Created: VN001'), findsOneWidget);
      expect(find.text('https://reset.example/abc'), findsOneWidget);
    });

    testWidgets('details page: name, code, phone, location, Active switch and pending items with Approve / Reject', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: QuickAccountDetailPage(
          store: store,
          uid: 'v1',
          accountStream: Stream.value(const Entry('v1', {'role': 'vendor', 'code': 'VN012', 'name': 'Ramu', 'phone': '9876543210', 'email': 'r@e.test', 'locationName': 'Rajahmundry', 'photoUrl': '', 'active': true})),
          itemsStream: Stream.value([_item('p1', status: 'pending'), _item('p2', status: 'pending'), _item('old', status: 'rejected')]),
          call: (name, data) async {
            calls.add('$name:${data['active'] ?? data['itemIds']}:${data['approved'] ?? ''}');
            return {};
          },
        ),
      ));
      await tester.pump();
      expect(find.text('Ramu'), findsOneWidget);
      expect(find.text('VN012 • Vendor'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Rajahmundry'), findsOneWidget);
      expect(find.text('Pending items (2)'), findsOneWidget);
      expect(find.text('Added by: Ravi Staff (ST001)'), findsWidgets);
      // Active switch
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('quick-active-switch'))).value, isTrue);
      await _tap(tester, find.byKey(const ValueKey('quick-active-switch')));
      await tester.pumpAndSettle();
      expect(calls.last, 'setQuickAccountActive:false:');
      // approve one, approve all
      await _tap(tester, find.byKey(const ValueKey('quick-approve-p1')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reviewQuickItems:[p1]:true');
      await _tap(tester, find.byKey(const ValueKey('quick-approve-all')));
      await tester.pumpAndSettle();
      expect(calls.last, anyOf('reviewQuickItems:[p1, p2]:true', 'reviewQuickItems:[p2, p1]:true'));
      // reject with a reason
      await _tap(tester, find.byKey(const ValueKey('quick-reject-p2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quick-reject-reason')), 'wrong price');
      await tester.tap(find.byKey(const ValueKey('quick-reject-confirm')));
      await tester.pumpAndSettle();
      expect(calls.last, 'reviewQuickItems:[p2]:false');
    });

    testWidgets('all items page: shows who added each item and where; filters; Approve all', (tester) async {
      _phone(tester);
      final store = await _store();
      final calls = <List<Object?>>[];
      final live = DateTime.now().subtract(const Duration(minutes: 5));
      await tester.pumpWidget(MaterialApp(
        home: QuickItemsAdminPage(
          store: store,
          stream: Stream.value([
            _item('p1', status: 'pending'),
            _item('p2', status: 'pending', location: 'loc-kak', more: {'ownerName': 'Sita Staff', 'ownerCode': 'ST002'}),
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
      await tester.tap(find.byKey(const ValueKey('quick-approve-all-pending')));
      await tester.pumpAndSettle();
      expect(calls.single.toSet(), {'p1', 'p2'});
      await _tap(tester, find.byKey(const ValueKey('quick-filter-live')));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-review-l1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-p1')), findsNothing);
      expect(find.byKey(const ValueKey('quick-reject-l1')), findsOneWidget, reason: 'a live item can be taken down');
      await _tap(tester, find.byKey(const ValueKey('quick-filter-all')));
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-review-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-review-l1')), findsOneWidget);
    });
  });

  group('customer website', () {
    testWidgets('shows "Showing items in", the live items with a countdown, and hides finished ones', (tester) async {
      _phone(tester);
      final store = await _store();
      store.quickLocationId = 'loc-raj';
      store.quickLocationAsked = true;
      store.catalog['quickItems'] = [
        _item('tom', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(hours: 2, minutes: 15)), more: {'name': 'Tomatoes'}),
        _item('over', starts: _now.subtract(const Duration(hours: 5)), ends: _now.subtract(const Duration(minutes: 1)), more: {'name': 'Gone Beans'}),
        _item('kak', location: 'loc-kak', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(hours: 1)), more: {'name': 'Kakinada Mangoes'}),
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
      expect(find.text('Kakinada Mangoes'), findsNothing);
      expect(find.text('Pending Peas'), findsNothing);
    });

    testWidgets('the same item disappears once its time is up', (tester) async {
      _phone(tester);
      final store = await _store();
      store.quickLocationId = 'loc-raj';
      store.quickLocationAsked = true;
      store.catalog['quickItems'] = [
        _item('tom', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(minutes: 30)), more: {'name': 'Tomatoes'}),
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

    testWidgets('Change lets the customer pick any location, and it is remembered on the device', (tester) async {
      _phone(tester);
      final store = await _store();
      store.quickLocationId = 'loc-raj';
      store.quickLocationAsked = true;
      store.catalog['quickItems'] = [
        _item('kak', location: 'loc-kak', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(hours: 1)), more: {'name': 'Kakinada Mangoes'}),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now)))));
      await tester.pump();
      expect(find.text('Kakinada Mangoes'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quick-change-location')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-location-loc-raj')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-location-loc-off')), findsNothing, reason: 'inactive location is not offered');
      await tester.tap(find.byKey(const ValueKey('quick-location-loc-kak')));
      await tester.pumpAndSettle();
      expect(find.text('Showing items in: Kakinada'), findsOneWidget);
      expect(find.text('Kakinada Mangoes'), findsOneWidget);
      // remembered
      final reopened = Store();
      await reopened.init();
      expect(reopened.quickLocationId, 'loc-kak');
      expect(reopened.quickLocationAsked, isTrue);
    });

    testWidgets('first visit: allow location -> the nearest listed location is chosen', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now, locate: () async => const _Position(16.96, 82.2)))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fresh items near you'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-prompt-allow')));
      await tester.pumpAndSettle();
      expect(store.quickLocationId, 'loc-kak', reason: 'nearest to 16.96, 82.2');
      expect(find.text('Showing items in: Kakinada'), findsOneWidget);
    });

    testWidgets('first visit: if location is denied they are asked to pick from the list', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now, locate: () async => throw StateError('denied')))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-prompt-allow')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a location'), findsOneWidget);
      expect(find.textContaining('please pick one from the list'), findsOneWidget);
      expect(store.quickLocationId, isEmpty);
      await tester.tap(find.byKey(const ValueKey('quick-location-loc-raj')));
      await tester.pumpAndSettle();
      expect(store.quickLocationId, 'loc-raj');
    });

    testWidgets('they can also choose from the list straight away, and are not asked again', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, now: () => _now)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-prompt-choose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-location-loc-kak')));
      await tester.pumpAndSettle();
      expect(store.quickLocationId, 'loc-kak');
      // a later visit does not ask again
      final again = Store();
      await again.init();
      again.catalog['locations'] = store.catalog['locations']!;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: again, now: () => _now)))));
      await tester.pumpAndSettle();
      expect(find.text('Fresh items near you'), findsNothing);
      expect(find.text('Showing items in: Kakinada'), findsOneWidget);
    });

    testWidgets('the admin preview never asks the first-visit question, and nothing shows without locations', (tester) async {
      _phone(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: store, prompt: false)))));
      await tester.pumpAndSettle();
      expect(find.text('Fresh items near you'), findsNothing);
      final empty = await _store(withLocations: false);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickFreshToday(store: empty)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-showing-in')), findsNothing);
    });

    testWidgets('a category page lists its live quick items for the chosen location', (tester) async {
      _phone(tester);
      final store = await _store();
      store.quickLocationId = 'loc-raj';
      store.quickLocationAsked = true;
      store.catalog['quickItems'] = [
        _item('tom', category: 'cat-1', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(hours: 2)), more: {'name': 'Tomatoes'}),
        _item('shirt', category: 'cat-9', starts: _now.subtract(const Duration(minutes: 5)), ends: _now.add(const Duration(hours: 2)), more: {'name': 'Shirts'}),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickCategoryItems(store: store, categoryId: 'cat-1', now: () => _now)))));
      await tester.pump();
      expect(find.text('Fresh today in Rajahmundry'), findsOneWidget);
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Shirts'), findsNothing);
    });
  });
}

class _Position {
  const _Position(this.latitude, this.longitude);
  final double latitude, longitude;
}

// A 1x1 transparent PNG, enough for the photo preview.
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
