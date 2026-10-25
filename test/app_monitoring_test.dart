import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/app_health.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/usage_report.dart';
import 'package:ecommerce_app/services/app_monitoring.dart';
import 'package:ecommerce_app/services/google_analytics.dart';
import 'package:ecommerce_app/services/usage.dart';
import 'package:ecommerce_app/ui/admin_setup_check.dart';

void main() {
  test('an error message loses emails, links and phone numbers, and keeps the same short id everywhere', () {
    expect(
      AppMonitoring.cleanMessage('StateError: no shop for ravi@example.com at https://x.test/a?b=1 phone 9876511111\n#0 main'),
      'StateError: no shop for <email> at <link> phone <number>',
    );
    expect(AppMonitoring.cleanMessage('x' * 300).length, 100);
    expect(AppMonitoring.fingerprint('StateError: Bad state'), AppMonitoring.fingerprint('StateError: Bad state'));
    expect(AppMonitoring.fingerprint('a'), isNot(AppMonitoring.fingerprint('b')));
    expect(AppMonitoring.fingerprint('a'), hasLength(8));
    expect(AppMonitoring.speedGroup(const Duration(milliseconds: 800)), 'under 1 s');
    expect(AppMonitoring.speedGroup(const Duration(milliseconds: 2500)), '2-4 s');
    expect(AppMonitoring.speedGroup(const Duration(seconds: 20)), 'over 8 s');
  });

  test('Google Analytics is off without a measurement id, and never gets emails, links or phone numbers', () {
    expect(googleAnalyticsOn, isFalse);
    startGoogleAnalytics(app: 'customer');
    expect(Usage.sinks, isEmpty);
    expect(cleanForAnalytics('ravi@example.com https://x.test/?a=1 9876511111 tomato'), '<email> <link> <number> tomato');
    expect(cleanForAnalytics('y' * 300).length, 100);
  });

  test('each error is counted once a run, and at most five different ones', () async {
    final batches = <Map<String, Object?>>[];
    final flutterHandler = FlutterError.onError, platformHandler = PlatformDispatcher.instance.onError;
    Usage.instance = Usage(app: 'vendor', deviceId: 'device-0123456789abcdef', platform: 'android', transport: (b) async => batches.add(b));
    addTearDown(() {
      Usage.instance?.dispose();
      Usage.instance = null;
      AppMonitoring.reset();
      FlutterError.onError = flutterHandler;
      PlatformDispatcher.instance.onError = platformHandler;
    });
    AppMonitoring.reset();
    // started without a binding's error handlers: only the counting is tested here
    AppMonitoring.report(StateError('before start'));
    expect(Usage.instance!.pending, 0, reason: 'nothing before start');
    AppMonitoring.start(app: 'vendor');
    for (var i = 0; i < 3; i++) {
      AppMonitoring.report(StateError('Bad state'));
    }
    for (var i = 0; i < 10; i++) {
      AppMonitoring.report(ArgumentError('wrong $i'));
    }
    AppMonitoring.report(StateError('lost'), crash: true);
    await Usage.instance!.flush();
    final events = [for (final b in batches) ...(b['events'] as List).cast<Map>()].where((e) => e['event'] == 'app_error').toList();
    expect(events, hasLength(AppMonitoring.maxErrors));
    expect(events.first['key'], startsWith('vendor/android/error/'));
    expect(events.first['label'], 'StateError: Bad state: Bad state');
  });

  test('the Setup check adds up starts, speed, errors and crashes per app', () {
    final report = UsageReport.build(const [
      Entry('2026-10-25~app_start', {'day': '2026-10-25', 'event': 'app_start', 'total': 4, 'keys': {
        'a': {'key': 'customer/android/under 1 s', 'label': 'under 1 s', 'count': 2},
        'b': {'key': 'customer/web/2-4 s', 'label': '2-4 s', 'count': 1},
        'c': {'key': 'vendor/android/1-2 s', 'label': '1-2 s', 'count': 1},
      }}),
      Entry('2026-10-25~app_error', {'day': '2026-10-25', 'event': 'app_error', 'total': 3, 'keys': {
        'd': {'key': 'customer/web/crash/1a2b3c4d', 'label': 'TypeError: null', 'count': 2},
        'e': {'key': 'customer/android/error/5e6f7a8b', 'label': 'RenderFlex overflowed', 'count': 1},
      }}),
    ]);
    final apps = {for (final a in AppHealth.build(report)) a.app: a};
    expect(apps.keys, ['customer', 'vendor', 'staff', 'admin']);
    final c = apps['customer']!;
    expect([c.starts, c.startsBy['android'], c.startsBy['web'], c.crashes, c.errors], [3, 2, 1, 2, 1]);
    expect(c.fastShare, closeTo(2 / 3, 0.001));
    expect(c.problems.first.label, 'TypeError: null');
    expect(apps['staff']!.starts, 0);
  });

  testWidgets('the Setup check page: what is set up, and each app\'s starts, speed and problems', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SetupCheckView(
          store: Store(live: true),
          audience: () async => {'on': 12, 'off': 3},
          load: () async => const [
            Entry('2026-10-25~app_start', {'day': '2026-10-25', 'event': 'app_start', 'total': 2, 'keys': {
              'a': {'key': 'vendor/android/under 1 s', 'label': 'under 1 s', 'count': 2},
            }}),
            Entry('2026-10-25~app_error', {'day': '2026-10-25', 'event': 'app_error', 'total': 1, 'keys': {
              'b': {'key': 'vendor/android/crash/1a2b3c4d', 'label': 'StateError: Bad state', 'count': 1},
            }}),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Customer app (Android and website): 12 people have notifications on.'), findsOneWidget);
    expect(find.text('Counted by every app, the website too (below).'), findsOneWidget);
    expect(find.textContaining('Not in this build: it needs the web measurement id'), findsOneWidget);
    expect(find.text('Started 2 times (android 2) • 100% showed the first screen in under 2 s'), findsOneWidget);
    expect(find.text('Crashes: 1 • errors: 0'), findsOneWidget);
    expect(find.text('1× android: StateError: Bad state'), findsOneWidget);
    expect(find.text('No starts counted yet.'), findsNWidgets(3));
  });
}
