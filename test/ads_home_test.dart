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
  testWidgets('desktop home: live ads appear in the unified column, with an Offers & Ads link', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store([for (var i = 1; i <= 4; i++) _ad('u$i', i)]);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byType(AdsColumn), findsOneWidget);
    expect(find.byType(AdBox), findsNWidgets(3));
    await tester.ensureVisible(find.byKey(const ValueKey('open-offers-ads')));
    await tester.tap(find.byKey(const ValueKey('open-offers-ads')));
    await tester.pumpAndSettle();
    expect(find.text('Offers & Ads'), findsWidgets);
    expect(find.byType(AdBox), findsNWidgets(4), reason: 'the page lists every live ad');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('phone home: one ad at a time with dots', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store([for (var i = 1; i <= 3; i++) _ad('u$i', i)]);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byType(AdsPager), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('radius: the home page shows only the ads whose circle covers the customer, and follows a change of location', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Entry circle(String id, int order, double km, double lat, double lng) =>
        Entry(id, {'title': id, 'contentType': 'text', 'order': order, 'radiusKm': km, 'radiusLat': lat, 'radiusLng': lng, 'radiusShopId': 's'});
    final store = await _store([
      circle('narsipatnam10', 1, 10, 17.667, 82.612),
      circle('anakapalle10', 2, 10, 17.691, 83.003),
      circle('wide100', 3, 100, 17.667, 82.612),
    ]);
    await store.setLocation('531116', 'Narsipatnam', lat: 17.67, lng: 82.62);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    List<String> shown() {
      final pager = tester.widget<AdsPager>(find.byType(AdsPager));
      return pager.ads.map((a) => a.id).toList()..sort();
    }

    expect(shown(), ['narsipatnam10', 'wide100']);
    await store.setLocation('531001', 'Anakapalle', lat: 17.691, lng: 83.003);
    await tester.pump();
    expect(shown(), ['anakapalle10', 'wide100'], reason: 'the customer moved: only the ads that cover the new place');
    await store.setLocation('500001', 'Hyderabad', lat: 17.385, lng: 78.486);
    await tester.pump();
    expect(find.byType(AdsPager), findsNothing, reason: 'far from every circle: no ads from this system');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
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
