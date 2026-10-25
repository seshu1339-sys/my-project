import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/modules/services/services_page.dart';

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets('width $width: Transport and Services are two big boxes under the offers, and the header no longer has Services', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();

      final transport = find.byKey(const ValueKey('home-box-transport'));
      final services = find.byKey(const ValueKey('home-box-services'));
      expect(transport, findsOneWidget);
      expect(services, findsOneWidget);
      expect(tester.getSize(transport), tester.getSize(services), reason: 'same size');
      expect(tester.getTopLeft(transport).dy, tester.getTopLeft(services).dy, reason: 'side by side');
      expect(tester.getTopLeft(transport).dx, lessThan(tester.getTopLeft(services).dx));
      expect(find.descendant(of: transport, matching: find.byType(Icon)), findsOneWidget);
      expect(find.descendant(of: transport, matching: find.text('Transport')), findsOneWidget);
      expect(find.descendant(of: services, matching: find.text('Services')), findsOneWidget);
      expect(find.byTooltip('Services'), findsNothing, reason: 'the header shortcut is gone');

      await tester.ensureVisible(services);
      await tester.pump();
      await tester.tap(services);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ServicesPage), findsOneWidget, reason: 'opens the same page as the old header shortcut');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
