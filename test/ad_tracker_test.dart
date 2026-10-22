import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/ad_tracker.dart';
import 'package:ecommerce_app/ui/ad_box.dart';
import 'package:ecommerce_app/ui/ads_column.dart';

Entry ad(String id) => Entry(id, {'title': 'Ad $id', 'contentType': 'text', 'order': int.parse(id.substring(2))});

class Sent {
  final batches = <Map<String, Object?>>[];
  List<Map<String, Object?>> events(String type) => [
    for (final b in batches) for (final e in (b['events'] as List).cast<Map<String, Object?>>()) if (e['type'] == type) e,
  ];
}

AdsTracker make(Sent sent, {DateTime Function()? now}) => AdsTracker(
  visitorId: 'visitor-0123456789abcdef',
  platform: 'web',
  now: now,
  transport: (b) async => sent.batches.add(b),
);

/// Ends a test: the boxes are removed (they report what they still owe), then the tracker stops its timer.
Future<void> done(WidgetTester tester, AdsTracker tracker) async {
  await tester.pumpWidget(const SizedBox());
  tracker.dispose();
}

void main() {
  group('the tracker', () {
    test('a view is sent once per ad per 30 minutes; time only follows a sent view', () async {
      var clock = DateTime(2026, 10, 26, 10);
      final sent = Sent();
      final t = make(sent, now: () => clock);
      t.view('a1', town: 'Narsipatnam');
      t.view('a1', town: 'Narsipatnam'); // a refresh
      clock = clock.add(const Duration(minutes: 29));
      t.view('a1', town: 'Narsipatnam');
      t.time('a2', 5); // never viewed: nothing to add time to
      t.time('a1', 4, town: 'Narsipatnam');
      await t.flush();
      expect(sent.events('view').length, 1);
      expect(sent.events('time').single['seconds'], 4);
      clock = clock.add(const Duration(minutes: 2));
      t.view('a1', town: 'Narsipatnam');
      await t.flush();
      expect(sent.events('view').length, 2, reason: '31 minutes after the first');
    });

    test('events go out in a batch per town, and a failed send never throws', () async {
      final sent = Sent();
      final t = make(sent);
      t.view('a1', town: 'Vizag');
      t.miss('a2', town: 'Guntur');
      t.tap('a1', town: 'Vizag');
      expect(t.pending, 3);
      await t.flush();
      expect(sent.batches.map((b) => b['town']).toSet(), {'Vizag', 'Guntur'});
      expect(sent.batches.first['visitorId'], 'visitor-0123456789abcdef');
      expect(sent.batches.first['platform'], 'web');
      expect(t.pending, 0);
      final failing = AdsTracker(visitorId: 'visitor-0123456789abcdef', platform: 'web', transport: (_) async => throw Exception('offline'));
      failing.tap('a1');
      await failing.flush();
    });

    testWidgets('the flush happens by itself after the interval', (tester) async {
      final sent = Sent();
      final t = make(sent);
      t.tap('a1');
      await tester.pump(const Duration(seconds: 9));
      expect(sent.batches, isNotEmpty);
    });
  });

  group('what the boxes report', () {
    final five = [for (var i = 1; i <= 5; i++) ad('ad$i')];

    Future<AdsTracker> show(WidgetTester tester, Sent sent, {Widget Function(Widget)? wrap}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tracker = make(sent);
      Widget column = SizedBox(
        width: 300,
        child: AdsColumn(ads: five, config: const AdsConfig(), onTap: (a) => tracker.tap(a.id, town: 'Narsipatnam'), tracker: tracker, town: 'Narsipatnam'),
      );
      if (wrap != null) column = wrap(column);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: column)))));
      return tracker;
    }

    testWidgets('an ad seen for a second counts as a view; its remaining seconds follow when it leaves the box', (tester) async {
      final sent = Sent();
      final tracker = await show(tester, sent);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tracker.pending, 0, reason: 'not yet a second');
      await tester.pump(const Duration(milliseconds: 1000));
      await tracker.flush();
      expect({for (final e in sent.events('view')) e['adId']}, {'ad1', 'ad2', 'ad3'});
      for (var s = 0; s < 8; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tracker.flush();
      expect(sent.events('time'), isNotEmpty, reason: 'some ad left its box after being seen');
      expect(sent.events('miss'), isEmpty);
      await done(tester, tracker);
    });

    testWidgets('a tab that is not active shows nothing: no views are counted', (tester) async {
      final sent = Sent();
      final tracker = await show(tester, sent);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var s = 0; s < 4; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tracker.flush();
      expect(sent.events('view'), isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await tracker.flush();
      expect(sent.events('view'), isNotEmpty, reason: 'counted once the tab is active again');
      await done(tester, tracker);
    });

    testWidgets('ads scrolled out of sight are never counted as seen; they are reported as missed when they change', (tester) async {
      final sent = Sent();
      final tracker = await show(tester, sent, wrap: (c) => Column(children: [const SizedBox(height: 1800), c]));
      for (var s = 0; s < 12; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tracker.flush();
      expect(sent.events('view'), isEmpty);
      expect(sent.events('miss'), isNotEmpty);
      await done(tester, tracker);
    });

    testWidgets('refreshing the page does not count the same ads again', (tester) async {
      final sent = Sent();
      final tracker = await show(tester, sent);
      await tester.pump(const Duration(seconds: 2));
      await tracker.flush();
      final first = sent.events('view').length;
      expect(first, 3);
      // a refresh builds the boxes again with the same device (same tracker)
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: AdsColumn(ads: five, config: const AdsConfig(), onTap: (_) {}, tracker: tracker, town: 'Narsipatnam')))));
      await tester.pump(const Duration(seconds: 2));
      await tracker.flush();
      expect(sent.events('view').length, first);
      await done(tester, tracker);
    });

    testWidgets('a tap is reported with the ad', (tester) async {
      final sent = Sent();
      final tracker = await show(tester, sent);
      await tester.tap(find.byType(AdBox).first);
      await tracker.flush();
      expect(sent.events('tap').single['adId'], 'ad1');
      await done(tester, tracker);
    });

    testWidgets('with no tracker (the admin previews) nothing is reported and nothing fails', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: AdsColumn(ads: five, config: const AdsConfig(), onTap: (_) {})))));
      for (var s = 0; s < 8; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
