import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/right_boxes.dart';
import 'package:ecommerce_app/domain/shop_ads.dart';
import 'package:ecommerce_app/services/ad_tracker.dart';
import 'package:ecommerce_app/services/shop_ad_payment.dart';
import 'package:ecommerce_app/ui/admin_right_boxes.dart';
import 'package:ecommerce_app/ui/right_ad_boxes.dart';
import 'package:ecommerce_app/ui/vendor_section_shop_ad.dart';

/// Records the server calls (Store.call is the one place every server call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'adId': 'rbox-1-new'};
  }
}

class _Sent {
  final batches = <Map<String, Object?>>[];
  List<Map<String, Object?>> events(String type) => [
    for (final b in batches) for (final e in (b['events'] as List).cast<Map<String, Object?>>()) if (e['type'] == type) e,
  ];
}

AdsTracker _tracker(_Sent sent) => AdsTracker(visitorId: 'visitor-0123456789abcdef', platform: 'web', transport: (b) async => sent.batches.add(b));

final _started = DateTime(2026, 10, 20, 9);
ShopAd _ad(String id, {int box = 1, String vendor = 'v1', String name = 'Lakshmi Kirana', bool live = true, DateTime? started, DateTime? ended}) =>
    ShopAd(id: id, box: box, vendorId: vendor, vendorName: name, vendorCode: vendor == 'v1' ? 'VEN-NRPM-116-001' : '', live: live, startedAt: started ?? _started, endedAt: ended);

void main() {
  group('shop ads', () {
    test('counts the Indian way, dates in words, and only shop-ad ids are shop ads (live first, newest first)', () {
      expect([shopAdCount(0), shopAdCount(999), shopAdCount(1234), shopAdCount(123456), shopAdCount(12345678)], ['0', '999', '1,234', '1,23,456', '1,23,45,678']);
      expect(shopAdDate(DateTime(2026, 10, 25)), '25 Oct 2026');
      expect(shopAdDate(null), '');
      expect(shopAdTime('2026-10-25T10:00:00.000'), DateTime(2026, 10, 25, 10));
      final ordered = shopAdsInOrder([
        Entry('rbox-2-old', {'box': 2, 'vendorId': 'v1', 'status': 'ended', 'startedAt': '2026-09-01T10:00:00.000'}),
        Entry('rbox-1-new', {'box': 1, 'vendorId': 'v1', 'status': 'live', 'startedAt': '2026-10-20T10:00:00.000'}),
        Entry('rbox-3-older', {'box': 3, 'vendorId': 'v1', 'status': 'ended', 'startedAt': '2026-08-01T10:00:00.000'}),
        const Entry('ad1', {'vendorId': 'v1', 'status': 'live'}),
      ]);
      expect(ordered.map((a) => a.id), ['rbox-1-new', 'rbox-2-old', 'rbox-3-older']);
      expect(ordered.first.live, isTrue);
      expect(ordered.first.box, 1);
      expect(rightBoxAdTitle('rbox-12-abc'), 'Shop ad, right box 12');
      expect(rightBoxAdTitle('ad1'), isNull);
      expect(const RightBox(1, 'a.jpg', '', '', adId: 'rbox-1-x').countsViews, isTrue);
      expect(const RightBox(1, '', '', '', adId: 'rbox-1-x').countsViews, isFalse, reason: 'no photo: the "your ad here" box is never counted');
      expect(const RightBox(1, 'a.jpg', '', '').countsViews, isFalse, reason: 'no vendor linked');
      expect(rightBoxAt(const Entry(rightBoxesDoc, {'box2AdId': 'rbox-2-y'}), 2).adId, 'rbox-2-y');
      expect(const OfflineShopAdPayment().id, 'offline');
      expect(const OfflineShopAdPayment().payLabel, isNull, reason: 'no in-app payment yet');
    });
  });

  group('the customer site', () {
    Future<void> show(WidgetTester tester, AdsTracker? tracker, List<String> targets) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const settings = [
        Entry(rightBoxesDoc, {
          'count': 3,
          'box1Image': 'http://x/a.jpg', 'box1AdId': 'rbox-1-abc', 'box1Target': 'shop:s1',
          'box2Image': 'http://x/b.jpg',
          'box3AdId': 'rbox-3-def',
        }),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RightAdBoxes(settings: settings, onTarget: targets.add, tracker: tracker, town: 'Narsipatnam')))));
    }

    testWidgets('a box with a vendor\'s shop ad counts one view after a second on screen; a box without an ad or without a photo counts nothing', (tester) async {
      final sent = _Sent();
      final tracker = _tracker(sent);
      await show(tester, tracker, []);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tracker.pending, 0, reason: 'not yet a second');
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(seconds: 3));
      await tracker.flush();
      expect([for (final e in sent.events('view')) e['adId']], ['rbox-1-abc'], reason: 'one view, only for the box with a photo and an ad');
      expect(sent.batches.single['town'], 'Narsipatnam');
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
    });

    testWidgets('tapping a box with a shop ad counts a tap and opens its link', (tester) async {
      final sent = _Sent();
      final tracker = _tracker(sent);
      final targets = <String>[];
      await show(tester, tracker, targets);
      await tester.tap(find.byKey(const ValueKey('right-box-1')));
      await tester.pump();
      await tracker.flush();
      expect(targets, ['shop:s1']);
      expect([for (final e in sent.events('tap')) e['adId']], ['rbox-1-abc']);
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
    });

    testWidgets('without a tracker (the admin\'s preview, the demo) nothing is counted and nothing breaks', (tester) async {
      final targets = <String>[];
      await show(tester, null, targets);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('right-box-1')));
      expect(targets, ['shop:s1']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the vendor app', () {
    Future<void> show(WidgetTester tester, ShopAdView view) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: view))));
    }

    testWidgets('the vendor ticks "I want an ad for my shop" and is told the office will call', (tester) async {
      final ticks = <bool>[];
      final done = Completer<void>();
      await show(tester, ShopAdView(interested: false, ads: const [], views: const {}, onInterest: (v) async {
        ticks.add(v);
        await done.future;
      }));
      expect(find.text('Ad for your shop'), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-ad-how')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('shop-ad-interest')));
      await tester.pump();
      expect(ticks, [true]);
      expect(find.byKey(const ValueKey('shop-ad-how')), findsOneWidget, reason: 'shown at once, while it saves');
      expect(find.textContaining('Our office will call you'), findsOneWidget);
      done.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Our office will contact you'), findsOneWidget);
    });

    testWidgets('a live ad shows its total views since it started (not live viewers); earlier ads keep their totals', (tester) async {
      await show(tester, ShopAdView(
        interested: true,
        ads: [_ad('rbox-1-new'), _ad('rbox-4-old', box: 4, live: false, started: DateTime(2026, 9, 1), ended: DateTime(2026, 9, 30))],
        views: const {'rbox-1-new': 1234, 'rbox-4-old': 98765},
        onInterest: (_) async {},
      ));
      expect(find.text('Your ad is live on the website'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('shop-ad-views-rbox-1-new'))).data, '1,234');
      expect(find.text('total views since 20 Oct 2026, when your ad started'), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-ad-how')), findsNothing, reason: 'the ad is already arranged');
      expect(tester.widget<Text>(find.byKey(const ValueKey('shop-ad-ended-rbox-4-old'))).data, '1 Sep 2026 to 30 Sep 2026: 98,765 views');
    });

    testWidgets('a live ad with no views yet shows 0', (tester) async {
      await show(tester, ShopAdView(interested: false, ads: [_ad('rbox-2-z', box: 2)], views: const {}, onInterest: (_) async {}));
      expect(tester.widget<Text>(find.byKey(const ValueKey('shop-ad-views-rbox-2-z'))).data, '0');
    });
  });

  testWidgets('admin: the vendors who want an ad, each box\'s vendor and total views, and linking, changing and ending a shop ad', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _RecordingStore();
    store.catalog['settings'] = [const Entry(rightBoxesDoc, {'count': 3, 'box1Image': 'http://x/a.jpg', 'box1AdId': 'rbox-1-abc', 'box2Image': 'http://x/b.jpg'})];
    final data = RightBoxShopAds(
      ads: [_ad('rbox-1-abc'), _ad('rbox-2-old', box: 2, vendor: 'v2', name: 'Ravi Fruits', live: false, started: DateTime(2026, 9, 1), ended: DateTime(2026, 9, 30))],
      views: const {'rbox-1-abc': 1234, 'rbox-2-old': 40},
      taps: const {'rbox-1-abc': 5},
      vendors: const [
        Entry('v1', {'name': 'Lakshmi Kirana', 'vendorCode': 'VEN-NRPM-116-001', 'status': 'approved', 'adInterest': true, 'adInterestAt': '2026-10-18T10:00:00.000'}),
        Entry('v2', {'name': 'Ravi Fruits', 'status': 'approved'}),
        Entry('v3', {'name': 'Anil Stores', 'status': 'approved', 'adInterest': true}),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminRightBoxesPage(store: store, shopAds: Stream.value(data)))));
    await tester.pump();

    // who wants an ad
    expect(find.text('Vendors who want an ad for their shop (2)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('shop-ad-wants-v1')), matching: find.text('Box 1, live')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('shop-ad-wants-v3')), matching: find.text('No ad yet')), findsOneWidget);
    expect(find.text('VEN-NRPM-116-001 • ticked 18 Oct 2026'), findsOneWidget);

    // box 1: the vendor, since when, the total views and taps
    expect(find.text('Lakshmi Kirana (VEN-NRPM-116-001) • since 20 Oct 2026'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('right-box-views-1'))).data, '1,234 views • 5 taps');
    expect(find.descendant(of: find.byKey(const ValueKey('right-box-shop-ad-2')), matching: find.text('Link to a vendor')), findsOneWidget);

    // link box 2: the vendors who want an ad come first
    await tester.tap(find.byKey(const ValueKey('link-right-box-2')));
    await tester.pumpAndSettle();
    final order = [for (final id in ['v1', 'v2', 'v3']) tester.getTopLeft(find.byKey(ValueKey('pick-vendor-$id'))).dy];
    expect(order[0] < order[1] && order[2] < order[1], isTrue, reason: 'Lakshmi and Anil want an ad, so they come before Ravi');
    await tester.enterText(find.byKey(const ValueKey('shop-ad-vendor-search')), 'anil');
    await tester.pump();
    expect(find.byKey(const ValueKey('pick-vendor-v1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-vendor-v3')));
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'assignRightBoxVendor');
    expect(store.calls.last.$2, {'box': 2, 'vendorId': 'v3'});

    // end box 1's ad
    await tester.tap(find.byKey(const ValueKey('end-right-box-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('end-shop-ad-confirm')));
    await tester.pumpAndSettle();
    expect(store.calls.last.$1, 'assignRightBoxVendor');
    expect(store.calls.last.$2, {'box': 1, 'vendorId': ''});

    // ended ads keep their totals
    await tester.tap(find.text('Ended shop ads (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Box 2 • Ravi Fruits • 1 Sep 2026 to 30 Sep 2026 • 40 views • 0 taps'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin: removing the last box ends its shop ad first', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _RecordingStore();
    store.catalog['settings'] = [const Entry(rightBoxesDoc, {'count': 2, 'box2Image': 'http://x/b.jpg', 'box2AdId': 'rbox-2-abc'})];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminRightBoxesPage(store: store, shopAds: Stream.value(RightBoxShopAds(ads: [_ad('rbox-2-abc', box: 2)]))))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remove-right-box')));
    await tester.pumpAndSettle();
    expect(find.text('This box has a shop ad. Removing the box ends the ad and takes it off the website.'), findsOneWidget);
    await tester.tap(find.text('Remove box').last);
    await tester.pump();
    expect(store.calls.first.$1, 'assignRightBoxVendor');
    expect(store.calls.first.$2, {'box': 2, 'vendorId': ''});
    await tester.pumpWidget(const SizedBox());
  });
}
