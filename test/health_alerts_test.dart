// AI Agent + Health System, part 1 (17 Nov 2026): problems with the most affected people first, then the most errors; the side of a
// problem and its phone models on App Health; the red banner of a burst alert and its Close; "Alerts on this device"; the admin's
// limits with their defaults and safe ranges. No server: seams and the demo store.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/health_status.dart';
import 'package:ecommerce_app/domain/support_limits.dart';
import 'package:ecommerce_app/services/health_watch.dart';
import 'package:ecommerce_app/ui/app_health_page.dart';
import 'package:ecommerce_app/ui/health_alert_banner.dart';
import 'package:ecommerce_app/ui/health_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Store store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
  });
  tearDown(() {
    HealthWatch.instance.set(HealthStatus.empty);
    store.dispose();
  });

  test('most affected people first, then most errors, then newest', () {
    final list = mostAffectedFirst([
      AppProblem(id: 'many-errors-one-person', app: 'vendor', platform: 'android', kind: 'api', message: 'a', count: 90, users: 1),
      AppProblem(id: 'seven-people', app: 'vendor', platform: 'android', kind: 'api', message: 'b', count: 9, users: 7),
      AppProblem(id: 'seven-people-more', app: 'vendor', platform: 'android', kind: 'api', message: 'c', count: 20, users: 7),
    ]);
    expect(list.map((p) => p.id), ['seven-people-more', 'seven-people', 'many-errors-one-person']);
  });

  test('a problem document: people, side, phone models, Android versions, screenshot', () {
    final p = AppProblem.from('x', {
      'app': 'vendor', 'platform': 'android', 'kind': 'tap', 'message': 'No answer to Save item', 'count': 6, 'users': 5, 'side': 'device',
      'devices': {'Xiaomi Redmi 9': 5, 'Galaxy A12': 1}, 'oses': {'Android 11': 6}, 'lastShot': 'case1', 'option': 'Save item', 'status': 'open',
    });
    expect(p.users, 5);
    expect(p.side, 'device');
    expect(AppProblem.topOf(p.devices), 'Xiaomi Redmi 9 ×5, Galaxy A12 ×1');
    expect(p.lastShot, 'case1');
    expect(AppProblem.from('y', {'side': 'nonsense'}).side, 'our');
  });

  testWidgets('App Health shows the most affected first, the side and the phones, and filters by side', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<(List<AppProblem>, List<Map<String, dynamic>>)> load(String app, String platform) async => (
      app == 'vendor'
          ? [
              AppProblem(id: 'lone', app: 'vendor', platform: 'android', kind: 'api', message: 'one person, many errors', count: 40, users: 1),
              AppProblem(id: 'wide', app: 'vendor', platform: 'android', kind: 'tap', message: 'No answer to Save item', count: 6, users: 5, side: 'device', devices: const {'Xiaomi Redmi 9': 6}),
              AppProblem(id: 'mine', app: 'vendor', platform: 'android', kind: 'location', message: 'Location off', count: 3, users: 3, side: 'user'),
            ]
          : <AppProblem>[],
      <Map<String, dynamic>>[],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppHealthPage(store: store, load: load))));
    await tester.pumpAndSettle();
    expect(find.text('Problems, most affected people first'), findsOneWidget);
    final wide = tester.getTopLeft(find.byKey(const ValueKey('app-health-problem-wide'))).dy;
    final mine = tester.getTopLeft(find.byKey(const ValueKey('app-health-problem-mine'))).dy;
    final lone = tester.getTopLeft(find.byKey(const ValueKey('app-health-problem-lone'))).dy;
    expect(wide, lessThan(mine));
    expect(mine, lessThan(lone), reason: '3 people before 1 person with 40 errors');
    expect(find.text('5 · 6×'), findsOneWidget);
    expect(find.text('Phones: Xiaomi Redmi 9 ×6'), findsOneWidget);
    expect(find.text('Device side (ఫోన్ మోడల్)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-health-side-user')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-health-problem-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-health-problem-wide')), findsNothing);
  });

  testWidgets('the red banner shows an open burst alert; Close takes it away', (tester) async {
    HealthWatch.instance.set(HealthStatus.empty, alerts: const [
      HealthAlert(id: 'vendor~android~tap~1', app: 'vendor', platform: 'android', message: 'No answer to Save item', screen: 'add_item', n: 6, minutes: 60),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HealthAlertBanner(store: store))));
    expect(find.byKey(const ValueKey('health-alert-banner')), findsOneWidget);
    expect(find.text('Vendor app: "No answer to Save item" 6 times in 60 min (add_item)'), findsOneWidget);
    expect(HealthWatch.instance.alertCount, 1, reason: 'the top-bar Health badge counts it');
    await tester.tap(find.byKey(const ValueKey('health-alert-close-vendor~android~tap~1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('health-alert-banner')), findsNothing);
  });

  testWidgets('"Alerts on this device" turns on and off, and says why when the browser blocks it', (tester) async {
    final turned = <bool>[];
    var fail = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HealthAlertsSwitch(store: store, isOn: () async => false, turn: (on) async {
      if (fail) throw StateError('Notifications are blocked for this site.');
      turned.add(on);
    }))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-alerts-switch')));
    await tester.pumpAndSettle();
    expect(turned, [true]);
    fail = true;
    await tester.tap(find.byKey(const ValueKey('health-alerts-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are blocked for this site.'), findsOneWidget);
  });

  test('the limits: defaults, safe ranges, saved values', () {
    expect(limitValue(const [], 'burstCount'), 6);
    expect(limitValue(const [], 'burstMinutes'), 60);
    expect(limitValue(const [], 'replyDays'), 1);
    expect(limitValue(const [Entry('health', {'burstCount': 10})], 'burstCount'), 10);
    expect(limitValue(const [Entry('health', {'burstCount': 1})], 'burstCount'), 6, reason: 'below the safe minimum');
    expect(supportAiOn(const []), isFalse, reason: 'AI is off until the admin turns it on');
  });

  testWidgets('the admin saves the limits into settings/health and settings/support; a wrong number is refused', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HealthLimitsCard(store: store)))));
    await tester.enterText(find.byKey(const ValueKey('health-limit-burstCount')), '1');
    await tester.tap(find.byKey(const ValueKey('health-limits-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('must be between 2 and 1000'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('health-limit-burstCount')), '8');
    await tester.enterText(find.byKey(const ValueKey('health-limit-replyDays')), '2');
    await tester.tap(find.byKey(const ValueKey('health-limit-aiOn')));
    await tester.tap(find.byKey(const ValueKey('health-limits-save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);
    expect(limitValue(store.entries('settings'), 'burstCount'), 8);
    expect(limitValue(store.entries('settings'), 'replyDays'), 2);
    expect(supportAiOn(store.entries('settings')), isTrue);
  });

  testWidgets('Spent this month: Google Cloud from the budgets, AI against ₹90 a month and ₹3 a day; stopped at the limit', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpentThisMonthCard(store: store, load: () async => (
      {'budgets': {'rs1': {'name': 'LOCAMARKET Rs 1 alert', 'cost': 28.57, 'budget': 1}, 'all': {'name': 'Auto Stop', 'cost': 30.1, 'budget': 200}}},
      {'inr': 12.5, 'calls': 240},
      {'inr': 0.42},
    )))));
    await tester.pumpAndSettle();
    expect(find.text('Google Cloud: ₹29 (budget "LOCAMARKET Rs 1 alert" ₹1.00)'), findsOneWidget);
    expect(find.textContaining('AI (Anthropic): ₹13 of ₹90 this month · today ₹0.42 of ₹3.00 · 240 AI answers'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-spent-ai-stopped')), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpentThisMonthCard(key: const ValueKey('b'), store: store, load: () async => (null, {'inr': 90.2, 'calls': 1800}, {'inr': 3.1})))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-spent-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-spent-ai-stopped')), findsOneWidget);
  });
}
