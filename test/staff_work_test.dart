// Staff work in the apps (owner, 13 Nov 2026): the pay rules (the same as functions/modules/staff-work/rules.js), the staff app's
// "My work", the vendor's "connect me to local staff", and the admin's ID report, staff pages and their search entries.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/staff_pay.dart';
import 'package:ecommerce_app/modules/flash/flash_chat_page.dart' show LocalStaffRequestButton;
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/admin_staff_work.dart';
import 'package:ecommerce_app/ui/staff_my_work.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  test('targets and pay: 50 a day, daily x days a month, own numbers win, the highest slab reached', () {
    expect(daysInMonth('2026-11'), 30);
    final all = targetsFor(null, null, '2026-11');
    expect([all.daily, all.monthly], [50, 1500]);
    final t = targetsFor({'dailyTarget': 40, 'slabs': [{'percent': 50, 'amount': 5000}, {'percent': 20, 'amount': 2000}]}, {'monthlyTarget': 1000}, '2026-11');
    expect([t.daily, t.monthly], [40, 1000]);
    final pay = payFor(450, t);
    expect([pay.percent, pay.amount, pay.slab?.percent, pay.next?.percent], [45, 2000, 20, 50]);
    expect(payFor(100, t).amount, 0);
    expect(groupCounts([('2026-11-09', 2), ('2026-11-10', 3), ('2026-11-16', 4)], 'week'), [('11-09', 5), ('11-16', 4)], reason: 'weeks start on Monday');
    expect(groupCounts([('2026-10-31', 1), ('2026-11-01', 2)], 'month'), [('2026-10', 1), ('2026-11', 2)]);
  });

  testWidgets('My work shows only the staff member\'s own numbers, the slab and the amount', (tester) async {
    final now = DateTime.utc(2026, 11, 13, 6);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StaffMyWorkView(
      now: now,
      days: {'2026-11-13': 12, '2026-11-12': 50},
      months: {'2026-11': 450, '2026-10': 900},
      config: {'dailyTarget': 50, 'slabs': [{'percent': 20, 'amount': 2000}, {'percent': 40, 'amount': 4000}, {'percent': 100, 'amount': 10000}]},
      own: {'monthlyTarget': 1000},
      linked: 7,
    )))));
    expect(find.byKey(const ValueKey('my-work-linked')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('12 / 50'), findsOneWidget);
    expect(find.text('450 / 1000'), findsOneWidget);
    expect(find.text('45.0%'), findsOneWidget);
    expect(find.textContaining('Slab reached: 40% → ₹4000'), findsOneWidget);
    expect(find.textContaining('This month by the slabs: ₹4000'), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a vendor asks to be connected to the staff of their area', (tester) async {
    final store = await _store();
    var asked = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LocalStaffRequestButton(store: store, send: () async { asked++; return {'status': 'open'}; }))));
    await tester.tap(find.byKey(const ValueKey('flash-local-staff')));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.textContaining('connect you to the staff of your area'), findsOneWidget);
    store.dispose();
  });

  testWidgets('the ID report: type an ID, press Enter, see the summary; a wrong ID says why', (tester) async {
    final store = await _store();
    final calls = <String>[];
    final downloads = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminIdReportPage(
      store: store,
      download: (name, bytes, type) async => downloads.add(name),
      call: (name, data) async {
        calls.add('$name ${data['code']}');
        if (data['code'] == 'BAD') throw StateError('Enter a Vendor ID (VEN-...), a service provider ID (SRV-...) or a Staff ID (STF-...).');
        return {
          'kind': 'vendor', 'code': 'VEN-NRPM-116-325', 'name': 'Ramu Kirana', 'phone': '9000000001', 'town': 'Narsipatnam', 'status': 'approved', 'area': 'Main road', 'pincode': '531116',
          'linkedStaff': {'staffCode': 'STF-NRPM-116-001'}, 'ratings': {'avg': 4.2, 'count': 9}, 'reports': {'count': 0},
          'activity': {'last30Days': 40, 'activeDays30': 12, 'lastUpdateDay': '2026-11-13'},
          'items': [{'name': 'Rice', 'price': 40, 'priceSetAt': '2026-11-13T05:00:00Z', 'active': true}],
          'priceChanges': [{'type': 'price', 'item': 'Rice', 'from': 38, 'to': 40, 'at': '2026-11-13T05:00:00Z', 'status': 'approved'}],
          'offers': <Object>[], 'ads': [{'title': 'Diwali', 'views': 120, 'taps': 8, 'startsAt': '', 'endsAt': ''}],
          'days': [{'day': '2026-11-12', 'updates': 3, 'items': 1, 'prices': 2, 'offers': 0}, {'day': '2026-11-13', 'updates': 5, 'items': 2, 'prices': 3, 'offers': 0}],
          'months': [{'month': '2026-11', 'updates': 8}],
        };
      },
    ))));
    await tester.enterText(find.byKey(const ValueKey('id-report-code')), 'BAD');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('id-report-error')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('id-report-code')), 'VEN-NRPM-116-325');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(calls.last, 'idReport VEN-NRPM-116-325');
    expect(find.textContaining('linked to STF-NRPM-116-001'), findsOneWidget);
    expect(find.textContaining('★ 4.2 (9)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('id-report-xlsx')));
    await tester.pumpAndSettle();
    expect(downloads.single, endsWith('.xlsx'));
    store.dispose();
  });

  test('the staff pages are in the admin search', () {
    for (final (q, key) in [('staff work', 'staffWork'), ('ranking', 'staffRanking'), ('id report', 'idReport'), ('staff links', 'staffLinks')]) {
      expect(searchAdminSettings(q).map((h) => h.sectionKey), contains(key), reason: q);
    }
  });
}
