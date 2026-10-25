import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/home_strip_band.dart';

Future<Store> _store({bool withStripProducts = true}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['categories'] = const [Entry('cat-vegetables', {'name': 'Fresh Vegetables', 'order': 1, 'active': true}), Entry('cat-care', {'name': 'Personal Care', 'order': 2, 'active': true})];
  store.catalog['products'] = [
    if (withStripProducts)
      for (var i = 0; i < 12; i++) Entry('veg$i', {'name': 'Veg $i', 'categoryId': 'cat-vegetables', 'price': 10 + i, 'stock': 5, 'active': true, 'order': i}),
    const Entry('soap', {'name': 'Soap', 'categoryId': 'cat-care', 'price': 20, 'stock': 5, 'active': true, 'order': 99}),
  ];
  return store;
}

void main() {
  for (final width in [1440.0, 1100.0, 800.0]) {
    testWidgets('width $width: Transport and Services fill the gap beside the product cards, equal width, from the offers down to the category tabs', (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();

      final transport = find.byKey(const ValueKey('home-box-transport'));
      final services = find.byKey(const ValueKey('home-box-services'));
      final band = find.byKey(const ValueKey('home-strip-band'));
      expect(band, findsOneWidget);
      final t = tester.getRect(transport), s = tester.getRect(services), b = tester.getRect(band);

      expect((t.width - s.width).abs(), lessThan(1), reason: 'equal width');
      expect(t.top, s.top);
      expect(t.height, s.height);
      expect(s.left - t.right, lessThan(12), reason: 'only a small gap between the two boxes');
      // They fill the space to the right of the whole product cards, up to the right edge of the band: no empty gap.
      final cards = ((b.width - HomeStripBand.minBoxesWidth) / HomeStripBand.cardPitch).floor();
      expect(t.left, closeTo(b.left + cards * HomeStripBand.cardPitch, 1.5));
      expect(s.right, closeTo(b.right, 1.5));
      // Taller than a product card, from the top of the band to the bottom of the Popular Products heading (just above the category tabs).
      expect(t.height, greaterThan(200));
      expect(t.top, closeTo(b.top, 1.5));
      final subtitle = tester.getRect(find.text('Products and services from your neighbourhood'));
      final tabs = tester.getRect(find.text('All'));
      expect(t.bottom, greaterThanOrEqualTo(subtitle.bottom - 1));
      expect(t.bottom, lessThanOrEqualTo(tabs.top + 1), reason: 'the boxes end at the category tabs line');
      expect(find.byTooltip('Services'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('phone (390): the two boxes sit below the product cards at full width', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-strip-band')), findsNothing, reason: 'no side-by-side band on a phone');
    final t = tester.getRect(find.byKey(const ValueKey('home-box-transport')));
    final s = tester.getRect(find.byKey(const ValueKey('home-box-services')));
    final strip = tester.getRect(find.text('Fresh Fruits & Vegetables'));
    expect(t.top, greaterThan(strip.bottom), reason: 'below the product cards');
    expect((t.width - s.width).abs(), lessThan(1));
    expect(t.top, s.top);
    expect(t.left, lessThan(24), reason: 'starts at the left edge of the page');
    expect(s.right, greaterThan(390 - 24), reason: 'reaches the right edge: full width');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('with no vegetable or fruit cards the boxes still show, below, full width', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(withStripProducts: false);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-box-transport')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-box-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-strip-band')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
