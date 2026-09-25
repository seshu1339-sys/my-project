// Confirms the admin's Page view drag-reorder actually reaches the real
// customer page (WireframeHome), not just the settings it writes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('Categories renders above Popular Products by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final categoriesY = tester.getTopLeft(find.text('Categories')).dy;
    final popularY = tester.getTopLeft(find.text('Popular Products')).dy;
    expect(categoriesY, lessThan(popularY));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('an admin-set order on section_popular moves it above Categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog.putIfAbsent('settings', () => []);
    store.catalog['settings']!.add(const Entry('section_popular', {'order': 5}));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final categoriesY = tester.getTopLeft(find.text('Categories')).dy;
    final popularY = tester.getTopLeft(find.text('Popular Products')).dy;
    expect(popularY, lessThan(categoriesY));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
