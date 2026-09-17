import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/data/store.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('storefront renders and searches at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await tester.pumpWidget(MarketApp(store: store));
      expect(find.bySemanticsLabel('App logo'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Plumbing');
      await tester.pump();
      expect(find.text('Plumbing visit'), findsOneWidget);
      expect(find.text('Farm-fresh vegetable box'), findsNothing);
      // The admin panel is a separate app/build target; it must never be
      // reachable from inside the customer app, in demo or live mode.
      expect(find.byTooltip('Business admin'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
  testWidgets('customer adds a product and opens the bag', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.ensureVisible(
      find.byTooltip('Add Farm-fresh vegetable box to bag'),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add Farm-fresh vegetable box to bag'));
    await tester.pump();
    expect(store.count, 1);
    await tester.ensureVisible(find.byTooltip('Shopping bag'));
    await tester.pump();
    await tester.tap(find.byTooltip('Shopping bag'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your shopping bag'), findsOneWidget);
    expect(find.text('Subtotal ₹249'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
