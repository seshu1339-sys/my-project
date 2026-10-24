import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/ad_box.dart';
import 'package:ecommerce_app/ui/ads_column.dart';

Entry _ad(String id, int order) => Entry(id, {'title': 'Ad $id', 'contentType': 'text', 'backgroundColor': '#FFEEAA', 'order': order});

Future<Store> _store(List<Entry> ads) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['ads'] = ads;
  return store;
}

void main() {
  testWidgets('the home page no longer builds the old ads column or pager (the Right Side Ad Boxes replaced them)', (tester) async {
    for (final width in [1440.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store([for (var i = 1; i <= 4; i++) _ad('u$i', i)]);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      expect(find.byType(AdsColumn), findsNothing, reason: 'width $width');
      expect(find.byType(AdsPager), findsNothing, reason: 'width $width');
      expect(find.byType(AdBox), findsNothing, reason: 'width $width');
      expect(find.byKey(const ValueKey('open-offers-ads')), findsNothing, reason: 'customers see only the photo boxes');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });

  testWidgets("radius: Today's Offers follow the same rule and the same location change", (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(const []);
    store.catalog['promotions'] = const [
      Entry('o1', {'name': 'Offer near Narsipatnam', 'placement': 'carousel', 'order': 1, 'radiusKm': 10, 'radiusLat': 17.667, 'radiusLng': 82.612, 'radiusShopId': 's'}),
      Entry('o2', {'name': 'Offer near Anakapalle', 'placement': 'carousel', 'order': 2, 'radiusKm': 10, 'radiusLat': 17.691, 'radiusLng': 83.003, 'radiusShopId': 's'}),
    ];
    await store.setLocation('531116', 'Narsipatnam', lat: 17.67, lng: 82.62);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Offer near Narsipatnam'), findsWidgets);
    expect(find.text('Offer near Anakapalle'), findsNothing);
    await store.setLocation('531001', 'Anakapalle', lat: 17.691, lng: 83.003);
    await tester.pump();
    expect(find.text('Offer near Anakapalle'), findsWidgets);
    expect(find.text('Offer near Narsipatnam'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('with no live ads the home page keeps its existing ad boxes', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store([Entry('expired', {'title': 'Old', 'endsAt': '2020-01-01T00:00:00'})]);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byType(AdsColumn), findsNothing);
    expect(find.byType(AdsPager), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
