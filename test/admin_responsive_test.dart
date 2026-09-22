// Width sweep for the admin screens this update touched (AppBar overflow menu, the
// EntryEditor preview dialog's fixed width). Uses the same tester.view.physicalSize pattern as
// test/widget_test.dart and test/home_layout_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
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

      final narrow = width < 680;
      // Below the breakpoint the 4 navigation buttons collapse into one menu; above it
      // they stay a plain row of labelled buttons. Either way nothing may overflow.
      expect(find.byTooltip('More'), narrow ? findsOneWidget : findsNothing);
      expect(find.text('Vendors'), narrow ? findsNothing : findsOneWidget);
      if (narrow) {
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        expect(find.text('Vendors'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10)); // dismiss the menu
        await tester.pump();
      }

      // The Product Image Library is one of the collections this update added to the
      // generic admin form; open its "Add new" form and the Preview dialog on it. The chip
      // row scrolls horizontally, so bring it into view first.
      await tester.ensureVisible(find.text('Product Image Library'));
      await tester.pump();
      await tester.tap(find.text('Product Image Library'));
      await tester.pump();
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
