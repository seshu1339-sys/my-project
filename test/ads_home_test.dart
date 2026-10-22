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
