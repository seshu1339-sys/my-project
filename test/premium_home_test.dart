import 'dart:async';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/today_offers.dart';
import 'package:ecommerce_app/modules/offerdisplay/offerdisplay_module.dart';
import 'package:ecommerce_app/modules/offerstore/offerstore_module.dart';
import 'package:ecommerce_app/modules/premium/premium_module.dart';
import 'package:ecommerce_app/modules/premiumscreen/premiumscreen_module.dart';
import 'package:ecommerce_app/modules/showcase/showcase_module.dart';
import 'package:ecommerce_app/services/server_clock.dart';
import 'package:ecommerce_app/ui/home_today_offers.dart';
import 'package:ecommerce_app/ui/shop_route_map.dart' show ShopRouteView;
import 'package:ecommerce_app/ui/vendor_premium_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePremium implements PremiumStatus {
  FakePremium(this.answer);
  final Stream<bool> answer;
  @override
  Stream<bool> watch(String vendorId) => answer;
}

TodaysOffer vendorOffer(int i, {String shop = 'near'}) {
  final now = DateTime.now();
  return TodaysOffer(
    vendorId: 'v$i',
    shopId: shop,
    photoUrl: '',
    price: 100 + i,
    submittedAt: now.subtract(Duration(minutes: 100 - i)),
    endsAt: now.add(const Duration(hours: 24)),
  );
}

Entry adminOffer(int slot) {
  final now = DateTime.now().toUtc();
  return Entry('admin$slot', {
    'placement': 'offer',
    'slot': slot,
    'name': 'Admin item $slot',
    'offerPrice': 25,
    'shopId': 'near',
    'startsAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
    'endsAt': now.add(const Duration(hours: 5)).toIso8601String(),
  });
}

Future<Store> openStore(List<Entry> adminOffers, {double? latitude = 17.667}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.latitude = latitude;
  store.longitude = latitude == null ? null : 82.611;
  store.catalog['shops'] = [
    const Entry('near', {'name': 'Lakshmi Kirana', 'latitude': 17.668, 'longitude': 82.612, 'radiusKm': 5}),
    const Entry('far', {'name': 'Far Shop', 'latitude': 19.0, 'longitude': 72.8, 'radiusKm': 5}),
  ];
  store.catalog['promotions'] = [
    for (var i = 1; i <= 6; i++) Entry('box$i', {'placement': 'carousel', 'order': i, 'name': 'Promotion', 'description': 'Old box $i', 'backgroundColor': todayOfferDefaultColors[i - 1]}),
    ...adminOffers,
  ];
  return store;
}

Future<void> show(WidgetTester tester, Store store, List<TodaysOffer> vendors, {double width = 1400, int visible = 6, int boxes = 6}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TodayOffersSection(
        store: store,
        boxes: [for (final p in store.entries('promotions')) if (p.text('placement') == 'carousel') p],
        appearance: Entry('promo', {'visibleCount': visible, 'animationMs': 3000}),
        speed: 200,
        vendorOffers: Stream.value(vendors),
        visible: boxes,
        seconds: 5,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> nextSet(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> clear(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // Owner, 6 Nov 2026: one box per paid vendor, 6 at a time on the website and 2 in the Android app, each turn the admin's seconds long;
  // with few vendors every other turn has none of them, so no vendor's box stays on longer than the set time.
  // Today, on a turn that is even and a multiple of 3 (5-second turns; the offers in these tests run around now).
  final base = DateTime.now().millisecondsSinceEpoch ~/ 30000 * 30000;
  void clock(int seconds) => ServerClock.debugSet(device: () => DateTime.fromMillisecondsSinceEpoch(base + seconds * 1000));

  testWidgets('admin offers first, then the paid vendors in the boxes left; promotions fill the rest; the next turn has no vendors', (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([adminOffer(4)]);
    await show(tester, store, [vendorOffer(1), vendorOffer(2)]);
    expect(find.text('Admin item 4'), findsOneWidget);
    expect(find.byType(VendorOfferBox), findsNWidgets(2));
    expect(find.text('Old box 3'), findsOneWidget);
    expect(find.text('Old box 4'), findsNothing, reason: '3 offers + 3 promotions = 6 boxes');
    final admin = tester.getTopLeft(find.byType(TodayOfferBox));
    final vendor = tester.getTopLeft(find.byKey(const ValueKey('vendor-offer-box-2')));
    expect(admin.dx, lessThan(vendor.dx));
    clock(5);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(VendorOfferBox), findsNothing, reason: 'two vendors for five boxes: they never stay longer than 5 seconds');
    expect(find.text('Admin item 4'), findsOneWidget, reason: "the admin's own offer stays");
    clock(10);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(VendorOfferBox), findsNWidgets(2), reason: 'and come back on the next turn');
    await clear(tester);
  });

  testWidgets('more vendors than boxes: a set at a time, each turn the admin seconds long, then back to the first', (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([adminOffer(1), adminOffer(2)]);
    await show(tester, store, [for (var i = 1; i <= 9; i++) vendorOffer(i)]);
    // 2 admin offers leave 4 boxes: vendors 1-4, then 5-8, then 9, then 1-4 again.
    expect(find.text('₹101'), findsOneWidget);
    expect(find.text('₹104'), findsOneWidget);
    expect(find.text('₹105'), findsNothing);
    clock(5);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('₹105'), findsOneWidget);
    expect(find.text('₹108'), findsOneWidget);
    expect(find.text('₹101'), findsNothing);
    clock(10);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('₹109'), findsOneWidget, reason: 'the last vendor is not skipped');
    clock(15);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('₹101'), findsOneWidget, reason: 'it loops to the first set');
    expect(find.text('Admin item 1'), findsOneWidget);
    await clear(tester);
  });

  testWidgets('in the Android app 2 boxes at a time, so every vendor comes on screen in turn', (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([]);
    await show(tester, store, [vendorOffer(1), vendorOffer(2), vendorOffer(3)], width: 390, visible: 2, boxes: 2);
    expect(find.text('₹101'), findsOneWidget);
    expect(find.text('₹102'), findsOneWidget);
    expect(find.text('₹103'), findsNothing);
    clock(5);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('₹103'), findsOneWidget);
    await clear(tester);
  });

  testWidgets("with the vendors' reach known, only vendors whose plan km covers the customer, and only running plans", (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TodayOffersSection(
          store: store,
          boxes: [for (final p in store.entries('promotions')) if (p.text('placement') == 'carousel') p],
          appearance: const Entry('promo', {'visibleCount': 6, 'animationMs': 3000}),
          vendorOffers: Stream.value([vendorOffer(1), vendorOffer(2), vendorOffer(3)]),
          showcase: Stream.value(const {
            'v1': ShowcaseEntry(vendorId: 'v1', shopId: 'near', shopName: 'Lakshmi', photoUrl: '', radiusKm: 5, active: true),
            'v2': ShowcaseEntry(vendorId: 'v2', shopId: 'near', shopName: 'Lakshmi', photoUrl: '', radiusKm: 5, active: false),
            'v3': ShowcaseEntry(vendorId: 'v3', shopId: 'near', shopName: 'Lakshmi', photoUrl: '', radiusKm: 0.05, active: true),
          }),
          seconds: 5,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('₹101'), findsOneWidget, reason: 'about 150 m away, the plan reaches 5 km');
    expect(find.text('₹102'), findsNothing, reason: 'the plan has ended');
    expect(find.text('₹103'), findsNothing, reason: 'the plan reaches only 50 m');
    await clear(tester);
  });

  testWidgets('a customer sees only offers of shops in the circle; with no location, none', (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([]);
    await show(tester, store, [vendorOffer(1), vendorOffer(2, shop: 'far')]);
    expect(find.byType(VendorOfferBox), findsOneWidget);
    expect(find.text('₹101'), findsOneWidget);
    await clear(tester);
    final nowhere = await openStore([], latitude: null);
    await show(tester, nowhere, [vendorOffer(1)]);
    expect(find.byType(VendorOfferBox), findsNothing);
    expect(find.text('Old box 1'), findsOneWidget, reason: 'the boxes go on as usual');
    await clear(tester);
  });

  testWidgets("a tap on a vendor box goes straight to the shop's place, address and route", (tester) async {
    addTearDown(ServerClock.debugReset);
    clock(0);
    final store = await openStore([]);
    await show(tester, store, [vendorOffer(1)]);
    await tester.tap(find.byType(VendorOfferBox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShopRouteView), findsOneWidget);
    await clear(tester);
  });

  testWidgets('the Today\'s Offer card shows only while the vendor is Premium, and comes back when they pay again', (tester) async {
    final store = await openStore([]);
    final answers = StreamController<bool>();
    addTearDown(answers.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VendorPremiumEntry(store: store, uid: 'v1', status: FakePremium(answers.stream))),
    ));
    expect(find.byType(PremiumEntryCard), findsNothing, reason: 'nothing while the answer is unknown');
    Future<void> say(bool premium) async {
      answers.add(premium);
      await tester.pump();
      await tester.pump();
    }

    await say(false);
    expect(find.byType(PremiumEntryCard), findsNothing, reason: 'a free vendor never sees it');
    await say(true);
    expect(find.byType(PremiumEntryCard), findsOneWidget);
    await say(false);
    expect(find.byType(PremiumEntryCard), findsNothing, reason: 'hidden when the plan ends');
    await say(true);
    expect(find.byType(PremiumEntryCard), findsOneWidget, reason: 'back after paying again');
  });
}
