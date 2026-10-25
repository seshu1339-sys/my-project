import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/usage_report.dart';
import 'package:ecommerce_app/ui/admin_analytics_people.dart';
import 'package:ecommerce_app/ui/admin_analytics_reports.dart';

const _daily = [
  Entry('2026-10-24~shop_call', {'day': '2026-10-24', 'event': 'shop_call', 'total': 3, 'keys': {
    'a': {'key': 'shopA', 'label': 'Lakshmi Kirana', 'town': 'Narsipatnam', 'count': 2},
    'b': {'key': 'shopB', 'label': 'Ravi Fruits', 'town': 'Narsipatnam', 'count': 1},
  }}),
  Entry('2026-10-25~shop_call', {'day': '2026-10-25', 'event': 'shop_call', 'total': 1, 'keys': {'a': {'key': 'shopA', 'label': 'Lakshmi Kirana', 'town': 'Narsipatnam', 'count': 1}}}),
  Entry('2026-10-25~shop_directions', {'day': '2026-10-25', 'event': 'shop_directions', 'total': 4, 'keys': {'b': {'key': 'shopB', 'label': 'Ravi Fruits', 'town': 'Narsipatnam', 'count': 4}}}),
  Entry('2026-10-25~search_no_result', {'day': '2026-10-25', 'event': 'search_no_result', 'total': 5, 'keys': {'d': {'key': 'dragon fruit', 'label': 'dragon fruit', 'town': '', 'count': 5}}}),
  Entry('2026-10-24~transport_click', {'day': '2026-10-24', 'event': 'transport_click', 'total': 7, 'keys': {}}),
  Entry('2026-10-25~button', {'day': '2026-10-25', 'event': 'button', 'total': 2, 'keys': {'x': {'key': 'header_cart', 'label': 'header_cart', 'count': 2}}}),
];

void main() {
  test('the report adds up the days: totals, what each event was about, several events per shop, and per day', () {
    final r = UsageReport.build(_daily);
    expect(r.total('shop_call'), 4);
    expect(r.top('shop_call').map((k) => '${k.label}:${k.count}'), ['Lakshmi Kirana:3', 'Ravi Fruits:1']);
    final shops = r.merged(['shop_call', 'shop_whatsapp', 'shop_directions']);
    expect(shops.map((s) => '${s.label}:${s.total}'), ['Ravi Fruits:5', 'Lakshmi Kirana:3']);
    expect(r.byDay('transport_click'), {'2026-10-24': 7});
    expect(r.total('nothing'), 0);
    final tables = usageTables(r);
    final features = tables.last;
    expect(features.rows.firstWhere((row) => row[1] == 'Header: bag')[2], 2);
    expect(features.rows.where((row) => row[2] == 0), isNotEmpty, reason: 'the screens and buttons nobody used are listed too');
    expect(tables.firstWhere((t) => t.title.startsWith('Searched but nothing found')).rows.single, ['dragon fruit', '', 5]);
  });

  test('a person\'s use over the range, the most active first', () {
    final people = PersonUsage.build(const [
      Entry('u1~2026-10-24', {'uid': 'u1', 'day': '2026-10-24', 'counts': {'shop_call': 2}, 'keys': {'shop_call~a': {'event': 'shop_call', 'key': 'shopA', 'label': 'Lakshmi Kirana', 'count': 2}}}),
      Entry('u1~2026-10-25', {'uid': 'u1', 'day': '2026-10-25', 'counts': {'search': 3}, 'keys': {}}),
      Entry('u2~2026-10-25', {'uid': 'u2', 'day': '2026-10-25', 'counts': {'search': 1}, 'keys': {}}),
    ]);
    expect(people.map((p) => '${p.uid}:${p.total}:${p.days.length}'), ['u1:5:2', 'u2:1:1']);
    expect(people.first.keys.values.single.label, 'shop_call: Lakshmi Kirana');
  });

  testWidgets('the reports page shows the totals and opens a table; the people page shows who and what', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = Store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnalyticsReportsView(store: store, load: (from, to) async => _daily, loadAds: () async => const [Entry('ad1', {'views': 12, 'taps': 3})]))));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('analytics-total-shop_call')), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('analytics-total-transport_click')), matching: find.text('7')), findsOneWidget);
    await tester.tap(find.text('Shops: calls, WhatsApp, directions'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi Fruits'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-excel')), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnalyticsPeopleView(
      store: store,
      load: (from, to) async => const [
        Entry('u1~2026-10-25', {'uid': 'u1', 'day': '2026-10-25', 'counts': {'shop_call': 2, 'search': 1}, 'keys': {'shop_call~a': {'event': 'shop_call', 'key': 'shopA', 'label': 'Lakshmi Kirana', 'count': 2}}}),
        Entry('u2~2026-10-25', {'uid': 'u2', 'day': '2026-10-25', 'counts': {'search': 1}, 'keys': {}}),
      ],
      labels: (uids) async => {'u1': {'name': 'Ravi', 'email': 'ravi@example.com', 'kind': 'customer'}, 'u2': {'email': 'kiran@example.com', 'kind': 'staff'}},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('2 people used the apps while signed in'), findsOneWidget);
    expect(find.text('Ravi • ravi@example.com'), findsOneWidget);
    expect(find.text('customer • 3 actions on 1 day'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('people-search')), 'staff');
    await tester.pump();
    expect(find.text('Ravi • ravi@example.com'), findsNothing);
    expect(find.text('kiran@example.com'), findsOneWidget);
    await tester.tap(find.text('kiran@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Searches: 1'), findsOneWidget);
  });
}
