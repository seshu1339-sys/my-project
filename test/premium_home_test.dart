import 'dart:async';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/today_offers.dart';
import 'package:ecommerce_app/modules/offerdisplay/offerdisplay_module.dart';
import 'package:ecommerce_app/modules/offerstore/offerstore_module.dart';
import 'package:ecommerce_app/modules/premium/premium_module.dart';
import 'package:ecommerce_app/modules/premiumscreen/premiumscreen_module.dart';
import 'package:ecommerce_app/ui/home_today_offers.dart';
import 'package:ecommerce_app/ui/shop_page.dart';
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

Future<void> show(WidgetTester tester, Store store, List<TodaysOffer> vendors, {double width = 1400, int visible = 6}) async {
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
  testWidgets('admin offers come first, then vendor offers, promotions fill what is left, and nothing moves', (tester) async {
    final store = await openStore([adminOffer(4)]);
    await show(tester, store, [vendorOffer(1), vendorOffer(2)]);
    expect(find.text('Admin item 4'), findsOneWidget);
    expect(find.byType(VendorOfferBox), findsNWidgets(2));
    expect(find.text('₹101'), findsOneWidget);
    expect(find.text('Old box 3'), findsOneWidget);
    expect(find.text('Old box 4'), findsNothing, reason: '3 offers + 3 promotions = 6 boxes');
    final admin = tester.getTopLeft(find.byType(TodayOfferBox));
    final vendor = tester.getTopLeft(find.byKey(const ValueKey('vendor-offer-box-2')));
    expect(admin.dx, lessThan(vendor.dx));
    await nextSet(tester);
    expect(find.text('Admin item 4'), findsOneWidget, reason: 'six or fewer: no rotation');
    await clear(tester);
  });

  testWidgets('more than 6 offers: the boxes change set by set, every offer gets its turn, then back to the first', (tester) async {
    final store = await openStore([adminOffer(1), adminOffer(2)]);
    await show(tester, store, [for (var i = 1; i <= 9; i++) vendorOffer(i)]);
    expect(find.text('Admin item 1'), findsOneWidget);
    expect(find.text('₹104'), findsOneWidget);
    expect(find.text('₹105'), findsNothing);
    expect(find.textContaining('Old box'), findsNothing, reason: 'only offers while they fill the boxes');
    await nextSet(tester);
    // 11 offers: the second set is the last 5, and the box left over takes the first offer again
    expect(find.text('₹105'), findsOneWidget);
    expect(find.text('₹109'), findsOneWidget, reason: 'the last offer is not skipped');
    expect(find.text('₹104'), findsNothing);
    expect(find.text('Admin item 1'), findsOneWidget);
    await nextSet(tester);
    expect(find.text('₹104'), findsOneWidget, reason: 'it loops to the first set');
    expect(find.text('Admin item 1'), findsOneWidget);
    await clear(tester);
  });

  testWidgets('on a phone they go 2 at a time, so all of them come on screen', (tester) async {
    final store = await openStore([adminOffer(1)]);
    await show(tester, store, [vendorOffer(1), vendorOffer(2), vendorOffer(3)], width: 390, visible: 2);
    expect(find.text('Admin item 1'), findsOneWidget);
    expect(find.text('₹101'), findsOneWidget);
    expect(find.text('₹103'), findsNothing);
    await nextSet(tester);
    expect(find.text('₹103'), findsOneWidget);
    await clear(tester);
  });

  testWidgets('a customer sees only offers of shops in the circle; with no location, none', (tester) async {
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

  testWidgets('a tap on a vendor box goes straight to the shop page', (tester) async {
    final store = await openStore([]);
    await show(tester, store, [vendorOffer(1)]);
    await tester.tap(find.byType(VendorOfferBox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShopPage), findsOneWidget);
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
