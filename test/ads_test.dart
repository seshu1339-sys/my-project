import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/ad_box.dart';
import 'package:ecommerce_app/ui/ad_transitions.dart';
import 'package:ecommerce_app/ui/ads_column.dart';

Entry ad(String id, [Map<String, dynamic> more = const {}]) => Entry(id, {'title': 'Ad $id', 'contentType': 'text', 'backgroundColor': '#FFEEAA', 'order': int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 0, ...more});

// Monday 2026-10-26 10:30
final monday = DateTime(2026, 10, 26, 10, 30);

void main() {
  group('which ads are live', () {
    test('status: pending / rejected / inactive / expired / scheduled / live', () {
      expect(adStatus(ad('a', {'status': 'pending'}), monday), 'pending');
      expect(adStatus(ad('a', {'status': 'rejected'}), monday), 'rejected');
      expect(adStatus(ad('a', {'active': false}), monday), 'inactive');
      expect(adStatus(ad('a', {'endsAt': '2026-10-01T00:00:00'}), monday), 'expired');
      expect(adStatus(ad('a', {'startsAt': '2026-11-01T00:00:00'}), monday), 'scheduled');
      expect(adStatus(ad('a', {'startsAt': '2026-10-01T00:00:00', 'endsAt': '2026-11-01T00:00:00'}), monday), 'live');
      expect(adStatus(ad('a'), monday), 'live', reason: 'no dates and no status: approved and on');
    });

    test('weekdays and daily time slots', () {
      expect(adLiveNow(ad('a', {'days': '1,3'}), monday), isTrue);
      expect(adLiveNow(ad('a', {'days': '2,4'}), monday), isFalse);
      expect(adLiveNow(ad('a', {'slots': '09:00-12:00,18:00-21:00'}), monday), isTrue);
      expect(adLiveNow(ad('a', {'slots': '18:00-21:00'}), monday), isFalse);
      expect(adLiveNow(ad('a', {'slots': '09:00-10:30'}), monday), isFalse, reason: 'the end minute is outside');
      expect(adLiveNow(ad('a', {'slots': '22:00-06:00'}), DateTime(2026, 10, 26, 23, 0)), isTrue, reason: 'past midnight');
      expect(adLiveNow(ad('a', {'slots': 'nonsense'}), monday), isTrue, reason: 'unreadable slot = all day');
      expect(adLiveNow(ad('a', {'status': 'pending'}), monday), isFalse);
    });

    test('location: ads for the customer\'s town, else the general ones; pinned first, then the admin\'s order', () {
      final all = [
        ad('3', {'locations': 'Narsipatnam'}),
        ad('1', {'locations': 'Vizag'}),
        ad('2', {'pinned': true, 'locations': 'Narsipatnam'}),
        ad('4'),
      ];
      expect(liveAds(all, monday, town: 'Narsipatnam').map((a) => a.id), ['2', '3']);
      expect(liveAds(all, monday, town: 'Vizag').map((a) => a.id), ['1']);
      expect(liveAds(all, monday, town: 'Guntur').map((a) => a.id), ['4'], reason: 'nothing for the town: the all-town ads');
      expect(liveAds(all, monday).map((a) => a.id), ['4'], reason: 'no town chosen: only the all-town ads');
    });

    test('the rotation shows 2x and 3x ads more often and never twice in a row', () {
      final cycle = adCycle([ad('1', {'rounds': 2}), ad('2'), ad('3', {'rounds': 3})]);
      expect(cycle.map((a) => a.id), ['1', '2', '3', '1', '3', '3']);
      const config = AdsConfig();
      expect(adSeconds(ad('1'), config), 5);
      expect(adSeconds(ad('1', {'seconds': 9}), config), 9);
    });

    test('tap actions become addresses the storefront understands', () {
      expect(adTarget(ad('1', {'tapAction': 'call', 'tapValue': '98765 43210'})), 'tel:+919876543210');
      expect(adTarget(ad('1', {'tapAction': 'whatsapp', 'tapValue': '9876543210'})), 'https://wa.me/919876543210');
      expect(adTarget(ad('1', {'tapAction': 'shop', 'tapValue': 'shop-a'})), 'shop:shop-a');
      expect(adTarget(ad('1', {'tapAction': 'link', 'tapValue': 'https://example.test'})), 'https://example.test');
    });

    test('common settings have the defaults asked for and are clamped', () {
      final d = AdsConfig.from(const []);
      expect((d.desktopSlots, d.mobileSlots, d.pauseOnHover, d.label), (3, 1, true, 'Ad'));
      final c = AdsConfig.from([const Entry('adsConfig', {'desktopSlots': 4, 'animation': 'cube', 'animationSpeed': 99, 'boxHeight': 10})]);
      expect(c.desktopSlots, 4);
      expect(c.animation, 'cube');
      expect(c.animationSpeed, 10);
      expect(c.boxHeight, 80);
      expect(AdsConfig.from([const Entry('adsConfig', {'animation': 'bogus'})]).animation, 'fade');
    });
  });

  group('rotation', () {
    test('every slot shows a different ad, and a slot never takes an ad another slot shows', () {
      final live = [for (var i = 1; i <= 5; i++) ad('$i')];
      final r = AdsRotation(adCycle(live), 3);
      expect(r.visibleSlots, 3);
      expect({for (var s = 0; s < 3; s++) r.current(s).id}.length, 3);
      for (var n = 0; n < 40; n++) {
        r.step(n % 3);
        expect({for (var s = 0; s < 3; s++) r.current(s).id}.length, 3, reason: 'after step $n');
      }
    });

    test('fewer ads than slots: only as many boxes as there are different ads', () {
      expect(AdsRotation(adCycle([ad('1'), ad('2')]), 3).visibleSlots, 2);
      expect(AdsRotation(adCycle([ad('1', {'rounds': 3})]), 3).visibleSlots, 1);
      expect(AdsRotation(const [], 3).visibleSlots, 0);
    });
  });

  group('animations', () {
    for (final type in adAnimations.keys) {
      testWidgets('$type renders at the start, the middle and the end', (tester) async {
        for (final t in [0.0, .25, .5, .75, 1.0]) {
          await tester.pumpWidget(MaterialApp(home: SizedBox(width: 300, height: 200, child: adTransitionFrame(type, t, const ColoredBox(color: Colors.red), const ColoredBox(color: Colors.blue)))));
          expect(tester.takeException(), isNull, reason: '$type at $t');
        }
      });
    }
  });

  group('the column', () {
    Future<void> show(WidgetTester tester, Size size, List<Entry> ads, {AdsConfig config = const AdsConfig(), ValueChanged<Entry>? onTap}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: 300, child: AdsColumn(ads: ads, config: config, onTap: onTap ?? (_) {}))))),
      ));
    }

    final five = [for (var i = 1; i <= 5; i++) ad('$i')];

    for (final size in const [Size(1366, 768), Size(1920, 1080), Size(3840, 2160)]) {
      testWidgets('3 equal boxes, all fully on screen at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await show(tester, size, five);
        final boxes = find.byType(AdBox);
        expect(boxes, findsNWidgets(3));
        final rects = [for (var i = 0; i < 3; i++) tester.getRect(boxes.at(i))];
        expect(rects.map((r) => r.height.round()).toSet().length, 1, reason: 'same height');
        expect(rects.map((r) => r.width.round()).toSet().length, 1, reason: 'same width');
        expect(rects.last.bottom, lessThanOrEqualTo(size.height), reason: 'the last box is not cut off');
        expect(rects.first.top, greaterThanOrEqualTo(0));
        expect(find.byKey(const ValueKey('ad-label')), findsNWidgets(3), reason: 'every ad is labelled');
      });
    }

    testWidgets('the boxes change one after another, not all at once', (tester) async {
      await show(tester, const Size(1920, 1080), five);
      String shown() => [for (var i = 0; i < 3; i++) (tester.widget(find.byType(AdBox).at(i)) as AdBox).ad.id].join(',');
      final start = shown();
      final changedAt = <int, int>{};
      var previous = start.split(',');
      for (var s = 1; s <= 12; s++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1) ~/ 1);
        final now = <String>[];
        for (var i = 0; i < 3; i++) {
          final boxes = find.byKey(ValueKey('ad-slot-$i'));
          final inside = find.descendant(of: boxes, matching: find.byType(AdBox));
          now.add((tester.widget(inside.last) as AdBox).ad.id);
        }
        for (var i = 0; i < 3; i++) {
          if (now[i] != previous[i]) changedAt.putIfAbsent(i, () => s);
        }
        previous = now;
      }
      expect(changedAt.length, 3, reason: 'every box changed within 24 seconds');
      expect(changedAt.values.toSet().length, greaterThan(1), reason: 'not all on the same second: $changedAt');
    });

    testWidgets('scrolling over the column lists every live ad; a few seconds later the automatic boxes return', (tester) async {
      await show(tester, const Size(1920, 1080), five);
      expect(find.byKey(const ValueKey('ads-browse')), findsNothing);
      final center = tester.getCenter(find.byKey(const ValueKey('ads-column')));
      final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump();
      expect(find.byKey(const ValueKey('ads-browse')), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('ads-browse')), const Offset(0, -300));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('ads-browse')), findsOneWidget, reason: 'still browsing 3 s after the last touch');
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('ads-browse')), findsNothing);
      expect(find.byType(AdBox), findsNWidgets(3));
    });

    testWidgets('tapping an ad reports it; nothing is shown with no live ads', (tester) async {
      final tapped = <String>[];
      await show(tester, const Size(1920, 1080), five, onTap: (a) => tapped.add(a.id));
      await tester.tap(find.byType(AdBox).first);
      expect(tapped, ['1']);
      await show(tester, const Size(1920, 1080), const []);
      expect(find.byType(AdBox), findsNothing);
    });

    testWidgets('the number of slots is a setting', (tester) async {
      await show(tester, const Size(1920, 1080), five, config: const AdsConfig(desktopSlots: 4));
      expect(find.byType(AdBox), findsNWidgets(4));
    });
  });

  group('the phone pager', () {
    testWidgets('one ad at a time, dots, swipe changes it', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdsPager(ads: [for (var i = 1; i <= 3; i++) ad('$i')], config: const AdsConfig(), onTap: (_) {}))));
      expect(find.byType(AdBox), findsOneWidget);
      expect((tester.widget(find.byType(AdBox)) as AdBox).ad.id, '1');
      expect(find.descendant(of: find.byKey(const ValueKey('ads-dots')), matching: find.byType(Container)), findsNWidgets(3));
      await tester.fling(find.byType(AdBox), const Offset(-300, 0), 800);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect((tester.widget(find.byType(AdBox)) as AdBox).ad.id, '2');
      await tester.fling(find.byType(AdBox), const Offset(300, 0), 800);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect((tester.widget(find.byType(AdBox)) as AdBox).ad.id, '1');
    });
  });

  testWidgets('an ad shows its image, text, badge, coupon and the Ad label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 300, height: 200, child: AdBox(ad: ad('1', {'contentType': 'imageText', 'imageUrl': '', 'title': 'Big Sale', 'text': 'Today only', 'badge': '50% Off', 'coupon': 'SAVE5'}), config: const AdsConfig(label: 'Sponsored')))));
    expect(find.text('Big Sale'), findsOneWidget);
    expect(find.text('Today only'), findsOneWidget);
    expect(find.text('50% Off'), findsOneWidget);
    expect(find.text('Code: SAVE5'), findsOneWidget);
    expect(find.text('Sponsored'), findsOneWidget);
  });
}
