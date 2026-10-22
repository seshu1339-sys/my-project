// Width sweep for the admin screens this update touched (AppBar overflow menu, the
// EntryEditor preview dialog's fixed width). Uses the same tester.view.physicalSize pattern as
// test/widget_test.dart and test/home_layout_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0, 768.0, 1024.0, 1200.0, 1440.0, 1920.0]) {
    testWidgets('admin studio has no overflow at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The main tabs, in this order, and nothing else in the tab bar.
      final labels = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
      expect(labels, ['Insights', 'Orders', 'Products', 'Vendors', 'Shops', 'Complaints', 'Promotions', 'Settings']);
      // Insights is the first page you see.
      expect(DefaultTabController.of(tester.element(find.byType(TabBar).first)).index, 0);
      // The top bar has only Search, AI Agent (and Sign out when live), each with a visible text label, and no bare icons.
      expect(find.widgetWithText(TextButton, 'Search'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'AI Agent'), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsNothing);
      expect(find.byTooltip('More'), findsNothing);

      // Settings holds the rest. The Product Image Library is one of the collections of the generic admin form:
      // open its "Add new" form and the Preview dialog on it.
      DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(7); // the Settings tab (it may be scrolled off a phone's tab bar)
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('settings-productImageLibrary')), 120, scrollable: find.descendant(of: find.byType(AdminSettingsPage), matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(find.byKey(const ValueKey('settings-productImageLibrary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-productImageLibrary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add new'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(find.text('productImageLibrary preview'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
