import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_staff_additions.dart';
import 'package:ecommerce_app/ui/photo_check.dart';

/// Records the server calls (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'status': 'ok'};
  }
}

const _vendor = Entry('add1', {
  'kind': 'vendor', 'status': 'pending', 'staffName': 'Kiran Kumar', 'staffCode': 'STF-NRPM-116-482', 'vendorCode': 'VEN-NRPM-116-321',
  'vendor': {'name': 'Lakshmi Kirana', 'phone': '9876543210', 'address': 'Main Road, Narsipatnam'}, 'town': 'Narsipatnam', 'pincode': '531116',
  'photoPaths': ['staffAdditions/s1/add1/vendor_1', 'staffAdditions/s1/add1/vendor_2', 'staffAdditions/s1/add1/vendor_3'],
  'items': [
    {'name': 'Tomato', 'unit': '1 kg', 'price': 30, 'photoPaths': ['staffAdditions/s1/add1/item1_1', 'staffAdditions/s1/add1/item1_2']},
  ],
  'submittedAt': '2026-10-25T09:00:00.000',
});
const _provider = Entry('add2', {
  'kind': 'provider', 'status': 'pending', 'staffName': 'Kiran Kumar', 'providerCode': 'SRV-NRPM-116-208', 'serviceName': 'Plumber', 'hourlyRate': 250,
  'provider': {'name': 'Suresh Kumar', 'phone': '9876522222'}, 'photoPaths': ['staffAdditions/s1/add2/work_1', 'staffAdditions/s1/add2/work_2'],
  'autoApproveHeld': ['work photo 1: the same photo was used before'],
  'submittedAt': '2026-10-25T10:00:00.000',
});

void main() {
  test('what a Google check found, in words', () {
    expect(photoCheckLines({'online': 'none'}).single.$1, 'Google: not found online');
    expect(photoCheckLines({'online': 'partial', 'pages': [{}]}).single.$1, 'Google: similar pictures online (1 page)');
    expect(photoCheckLines({'online': 'full', 'pages': [{}, {}]}).single.$1, 'Google: this picture is online, probably copied (2 pages)');
    expect(photoCheckLines({'online': 'limit'}).single.$1, "Google check not done: this month's free checks are used up");
    expect(photoCheckLines({'online': 'error', 'note': 'API disabled'}).single.$1, 'Google check could not run: API disabled');
    final dup = photoCheckLines({'online': 'none', 'duplicates': [{'kind': 'vendor', 'label': 'shop photo 1', 'exact': true}, {'kind': 'staffAddition', 'label': 'item 1 photo 2', 'exact': false}]});
    expect(dup.map((l) => l.$1), ['Google: not found online', "Same file as a vendor's shop photo 1", 'Same picture as a staff addition (item 1 photo 2)']);
    expect(photoCheckId('staffAdditions/s1/add1/vendor_1'), 'staffAdditions~s1~add1~vendor_1');
    expect(photoCheckMonth(DateTime.utc(2026, 10, 31, 20)), '2026-11', reason: 'the month in India');
    expect(photoCheckUsageText({'scans': 37, 'limit': 1000}), 'Google checks this month: 37 of 1000 free');
    expect(photoCheckUsageText(null), 'Google checks this month: 0 of 1000 free');
  });

  testWidgets('the review: Approve works only once every photo is checked with Google; then it goes to the server; Reject needs a reason', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _RecordingStore();
    final checks = {for (final id in ['add1', 'add2']) id: StreamController<Map<String, Map<String, dynamic>>>()};
    addTearDown(() {
      for (final c in checks.values) {
        c.close();
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: StaffAdditionsReviewPage(
        store: store,
        additions: Stream.value(const [_provider, _vendor]),
        checksFor: (id) => checks[id]!.stream,
        photo: (path) => SizedBox(width: 200, height: 60, child: Text('photo $path')),
        usage: const Text('Google checks this month: 3 of 1000 free'),
      ),
    ));
    await tester.pump();
    expect(find.text('2 waiting for approval, oldest first. Check every photo with Google, then approve: it goes live at once.'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('staff-review-add1'))).dy < tester.getTopLeft(find.byKey(const ValueKey('staff-review-add2'))).dy, isTrue, reason: 'oldest first');
    expect(find.text('Lakshmi Kirana'), findsOneWidget);
    expect(find.text('Vendor ID: VEN-NRPM-116-321 • Phone: 9876543210'), findsOneWidget);
    expect(find.text('Added by Kiran Kumar (STF-NRPM-116-482) on 25 Oct 2026'), findsOneWidget);
    expect(find.text('Item 1: Tomato • ₹30 for 1 kg'), findsOneWidget);
    expect(find.text('Suresh Kumar • Plumber'), findsOneWidget);
    expect(find.text('Charge: ₹250 per hour'), findsOneWidget);
    expect(find.text('Not auto-approved, the Google check found:\n• work photo 1: the same photo was used before'), findsOneWidget);
    expect(find.text('0 of 5 photos checked with Google'), findsOneWidget);
    FilledButton approve() => tester.widget<FilledButton>(find.byKey(const ValueKey('staff-approve-add1')));
    expect(approve().onPressed, isNull, reason: 'not before every photo is checked');

    await tester.tap(find.byKey(const ValueKey('google-check-staffAdditions/s1/add1/vendor_1')));
    await tester.pump();
    expect(store.calls.last.$1, 'checkPhoto');
    expect(store.calls.last.$2, {'path': 'staffAdditions/s1/add1/vendor_1'});

    // the results arrive (one photo is online, one was used before)
    checks['add1']!.add({
      'staffAdditions/s1/add1/vendor_1': {'online': 'full', 'pages': [{'url': 'https://stock.example', 'title': 'Stock photos'}]},
      'staffAdditions/s1/add1/vendor_2': {'online': 'none'},
      'staffAdditions/s1/add1/vendor_3': {'online': 'none', 'duplicates': [{'kind': 'vendor', 'label': 'shop photo 1', 'exact': true}]},
      'staffAdditions/s1/add1/item1_1': {'online': 'none'},
    });
    await tester.pump();
    expect(find.text('4 of 5 photos checked with Google'), findsOneWidget);
    expect(find.text('Google: this picture is online, probably copied (1 page)'), findsOneWidget);
    expect(find.text('Stock photos'), findsOneWidget);
    expect(find.text("Same file as a vendor's shop photo 1"), findsOneWidget);
    expect(approve().onPressed, isNull);
    checks['add1']!.add({
      for (final p in ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']) 'staffAdditions/s1/add1/$p': {'online': 'none'},
    });
    await tester.pump();
    expect(find.text('5 of 5 photos checked with Google'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-approve-add1')));
    await tester.pump();
    expect(store.calls.last.$1, 'reviewStaffAddition');
    expect(store.calls.last.$2, {'additionId': 'add1', 'approved': true});

    // reject the provider with a reason
    await tester.tap(find.byKey(const ValueKey('staff-reject-add2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('staff-reject-reason-add2')), 'Work photos are from the internet');
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();
    expect(store.calls.last.$2, {'additionId': 'add2', 'approved': false, 'reason': 'Work photos are from the internet'});
    await tester.pumpWidget(const SizedBox());
  });
}
