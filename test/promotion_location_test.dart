// Confirms location-targeted promotions actually reach only the customers
// they're targeted at on the real customer page (WireframeHome), not just
// that the matching function itself returns the right booleans in isolation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('a pincode-targeted promotion only shows to that pincode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    // The demo catalog seeds its own sample carousel entries; clear them so
    // this test's single promo is the only carousel page and is always the
    // one visible, rather than being buried on a later PageView page.
    store.catalog['promotions']?.clear();
    await store.save(
      'promotions',
      const Entry('promo1', {
        'name': 'Only for 560001',
        'placement': 'carousel',
        'targetPincode': '560001',
      }),
    );
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    // No pincode set yet: a pincode-targeted promo must not show to an
    // unknown location.
    expect(find.text('Only for 560001'), findsNothing);

    await store.setLocation('560002', '');
    await tester.pump();
    expect(find.text('Only for 560001'), findsNothing);

    await store.setLocation('560001', '');
    await tester.pump();
    expect(find.text('Only for 560001'), findsWidgets);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('an untargeted promotion still shows regardless of pincode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['promotions']?.clear();
    await store.save(
      'promotions',
      const Entry('promo2', {'name': 'Everywhere offer', 'placement': 'carousel'}),
    );
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Everywhere offer'), findsWidgets);

    await store.setLocation('999999', '');
    await tester.pump();
    expect(find.text('Everywhere offer'), findsWidgets);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
