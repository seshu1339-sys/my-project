// Confirms the admin's Page view drag-reorder actually reaches the real
// customer page (WireframeHome), not just the settings it writes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('the Categories section and the All Categories button are gone from the home page', (tester) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Browse your everyday essentials'), findsNothing);
    expect(find.text('All Categories'), findsNothing);
    expect(find.text('Popular Products'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('an admin-set order on section_popular moves it below Local Services', (tester) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog.putIfAbsent('settings', () => []);
    store.catalog['settings']!.add(const Entry('section_popular', {'order': 50}));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final popularY = tester.getTopLeft(find.text('Popular Products')).dy;
    final servicesY = tester.getTopLeft(find.text('Local Services')).dy;
    expect(servicesY, lessThan(popularY));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
