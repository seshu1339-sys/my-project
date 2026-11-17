// Health check + App Health, parts 2 and 3 (owner spec F, G, H, 17 Nov 2026): the status the panel reads, the red marks, the
// "what is not working?" answer, the Health page (AI explain only when ON), the App Health tabs, "Report a problem", and the app's
// problem reports (key failures, server errors, the cap). No server and no AI: seams and fakes.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/health_status.dart';
import 'package:ecommerce_app/services/app_monitoring.dart';
import 'package:ecommerce_app/services/health_watch.dart';
import 'package:ecommerce_app/ui/app_health_page.dart';
import 'package:ecommerce_app/ui/health_marks.dart';
import 'package:ecommerce_app/ui/health_page.dart';
import 'package:ecommerce_app/ui/report_problem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthStatus _status() => HealthStatus.from({
  'at': DateTime.utc(2026, 11, 17, 23, 50),
  'checks': {
    'site': {'id': 'site:https://x-vendor.web.app/', 'name': 'Vendor web app opens', 'group': 'Pages', 'ok': false, 'error': 'HTTP 503', 'registryIds': ['page.tab.vendors'], 'since': DateTime.utc(2026, 11, 17, 23, 50)},
    'ads': {'id': 'ads:radius', 'name': 'Location / radius ads reach the right km', 'group': 'Ads', 'ok': true, 'registryIds': ['page.ads'], 'ms': 3},
  },
  'serverErrors': [
    {'service': 'placeorder', 'message': 'TypeError: x is undefined', 'count': 4, 'last': '2026-11-17T09:00:00Z'},
  ],
});

void main() {
  tearDown(() => HealthWatch.instance.set(HealthStatus.empty));

  test('the status: failing first, the red-mark IDs, and "what is not working?" in plain lines', () {
    final s = _status();
    expect(s.checks.first.ok, isFalse, reason: 'failures first');
    expect(s.failingRegistryIds, {'page.tab.vendors'});
    expect(s.failingFor('page.ads'), isEmpty);
    final now = DateTime.utc(2026, 11, 18, 10);
    final answer = notWorkingAnswer(s, now: now, newReports: 2, recentProblems: [
      AppProblem(id: 'a', app: 'vendor', platform: 'android', kind: 'otp', message: 'OTP failed', count: 3, lastAt: now.subtract(const Duration(hours: 2))),
      AppProblem(id: 'b', app: 'staff', platform: 'android', kind: 'upload', message: 'old', lastAt: now.subtract(const Duration(days: 3))),
    ]);
    expect(answer, contains('Vendor web app opens — HTTP 503'));
    expect(answer, contains('Server placeorder: TypeError'));
    expect(answer, contains('Vendor app: 3 problems'));
    expect(answer, isNot(contains('Staff app')), reason: 'only the last 24 hours');
    expect(answer, contains('2 new "Report a problem"'));
    expect(notWorkingAnswer(HealthStatus.from({'at': DateTime.utc(2026, 11, 17), 'checks': {'a': {'id': 'a', 'name': 'A', 'ok': true}}})), contains('Everything works'));
    expect(countsByKind([
      AppProblem(id: '1', app: 'v', platform: 'android', kind: 'otp', message: 'a', count: 2),
      AppProblem(id: '2', app: 'v', platform: 'android', kind: 'crash', message: 'b', count: 5),
      AppProblem(id: '3', app: 'v', platform: 'android', kind: 'otp', message: 'c'),
    ]), {'crash': 5, 'otp': 3});
  });

  testWidgets('a failing option gets a red mark; a working one none', (tester) async {
    HealthWatch.instance.set(_status());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [HealthMark(registryId: 'page.tab.vendors'), HealthMark(registryId: 'page.ads')]))));
    expect(find.byKey(const ValueKey('health-mark-page.tab.vendors')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-mark-page.ads')), findsNothing);
  });

  group('pages', () {
    late Store store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
    });
    tearDown(() => store.dispose());

    testWidgets('Health: red check with the raw error; AI explain only when it is ON', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var ran = 0;
      final page = HealthPage(store: store, status: _status(), runNow: () async { ran++; return {'ok': false, 'failed': 1}; }, explain: (c) async => 'కారణం: సైట్ డౌన్.\n```\nFix the vendor site\n```');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
      expect(find.byKey(const ValueKey('health-summary')), findsOneWidget);
      expect(find.textContaining('1 of 2 checks failing'), findsOneWidget);
      expect(find.text('HTTP 503'), findsOneWidget);
      expect(find.textContaining('placeorder: TypeError'), findsOneWidget);
      expect(find.byKey(const ValueKey('health-explain-site:https://x-vendor.web.app/')), findsNothing, reason: 'AI explain is OFF: no AI button');
      await tester.tap(find.byKey(const ValueKey('health-run-now')));
      await tester.pumpAndSettle();
      expect(ran, 1);
      expect(find.text('1 checks failed.'), findsOneWidget);

      store.catalog['settings'] = [...store.entries('settings'), const Entry('agent', {'aiExplain': 'true'})];
      store.notifyListeners();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('health-explain-site:https://x-vendor.web.app/')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('health-explain-text')), findsOneWidget);
      expect(find.text('Copy Claude Code prompt'), findsOneWidget);
    });

    testWidgets('App Health: Vendor / Staff / User tabs, counts per problem, newest first, the reports', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final asked = <String>[];
      Future<(List<AppProblem>, List<Map<String, dynamic>>)> load(String app, String platform) async {
        asked.add('$app/$platform');
        if (app != 'vendor') return (<AppProblem>[], <Map<String, dynamic>>[]);
        return (
          newestFirst([
            AppProblem(id: 'old', app: 'vendor', platform: 'android', kind: 'upload', message: 'Photo upload (catalog): unauthorized', count: 2, lastAt: DateTime(2026, 11, 16), userCode: 'VEN-NRPM-116-325'),
            AppProblem(id: 'new', app: 'vendor', platform: 'android', kind: 'otp', message: 'verifyEmailLoginCode: invalid-argument', count: 5, lastAt: DateTime(2026, 11, 17), version: '1.0.12+22'),
          ]),
          [{'id': 'r1', 'text': 'Save button does nothing', 'status': 'new', 'userCode': 'VEN-NRPM-116-325'}],
        );
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppHealthPage(store: store, load: load))));
      await tester.pumpAndSettle();
      for (final tab in ['Vendor app', 'Staff app', 'User app', 'Website', 'Admin panel']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.textContaining('OTP failed (OTP): 5'), findsOneWidget);
      expect(find.textContaining('Photo upload failed (ఫోటో అప్‌లోడ్): 2'), findsOneWidget);
      final newer = tester.getTopLeft(find.byKey(const ValueKey('app-health-problem-new'))).dy;
      final older = tester.getTopLeft(find.byKey(const ValueKey('app-health-problem-old'))).dy;
      expect(newer, lessThan(older), reason: 'newest first');
      expect(find.text('Save button does nothing'), findsOneWidget);
      await tester.tap(find.text('Staff app'));
      await tester.pumpAndSettle();
      expect(asked, contains('staff/android'));
      expect(find.byKey(const ValueKey('app-health-none')), findsOneWidget);
    });

    testWidgets('Report a problem sends the words with the app details; empty text is refused', (tester) async {
      final sent = <Map<String, Object?>>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportProblemButton(store: store, send: (d) async => sent.add(d)))));
      await tester.tap(find.byKey(const ValueKey('report-problem')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-problem-send')));
      await tester.pump();
      expect(find.byKey(const ValueKey('report-problem-error')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('report-problem-text')), 'ఫోటో అప్‌లోడ్ కావట్లేదు');
      await tester.tap(find.byKey(const ValueKey('report-problem-send')));
      await tester.pumpAndSettle();
      expect(sent.single['text'], 'ఫోటో అప్‌లోడ్ కావట్లేదు');
      expect(sent.single.containsKey('app'), isTrue);
      expect(find.byKey(const ValueKey('report-problem-sent')), findsOneWidget);
    });
  });

  group('the app reports its problems', () {
    setUp(() {
      AppMonitoring.reset();
      AppMonitoring.testSink = [];
    });
    tearDown(() {
      AppMonitoring.testSink = null;
      AppMonitoring.reset();
    });

    test('login / OTP calls always count; other calls only when the server broke; the screen goes with it', () async {
      AppMonitoring.start(app: 'vendor');
      AppMonitoring.screen = 'vendor_products';
      AppMonitoring.callFailed('verifyEmailLoginCode', 'invalid-argument', 'Wrong code');
      AppMonitoring.callFailed('enterRole', 'permission-denied', null);
      AppMonitoring.callFailed('submitVendorChange', 'invalid-argument', 'Fill in the price');
      AppMonitoring.callFailed('submitVendorChange', 'internal', 'boom');
      AppMonitoring.fail('upload', 'Photo upload (catalog): unauthorized');
      AppMonitoring.fail('location', 'Location permission denied (register)');
      AppMonitoring.fail('upload', 'Photo upload (catalog): unauthorized');
      await AppMonitoring.flushNow();
      final problems = (AppMonitoring.testSink!.single['problems'] as List).cast<Map>();
      expect([for (final p in problems) p['kind']], ['otp', 'login', 'api', 'upload', 'location'], reason: 'the "fill in" answer is not a problem; a repeat is sent once');
      expect(problems.first['screen'], 'vendor_products');
      expect(AppMonitoring.testSink!.single['app'], 'vendor');
    });

    test('at most maxErrors different problems a run', () async {
      AppMonitoring.start(app: 'staff');
      for (var i = 0; i < 20; i++) {
        AppMonitoring.fail('api', 'call $i: internal');
      }
      await AppMonitoring.flushNow();
      expect((AppMonitoring.testSink!.single['problems'] as List).length, AppMonitoring.maxErrors);
    });
  });
}
