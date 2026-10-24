import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/color_picker_field.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  // Tall enough to fit every field in this particular form without
  // scrolling -- simpler than scrolling to each one in turn.
  void setTallSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    "Scrolling Text Settings' textColor/backgroundColor/borderColor are real color pickers, and fontWeight is a Bold-style dropdown, not raw text boxes",
    (tester) async {
      final store = await openStore();
      setTallSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: EntryEditor(store: store, collection: 'scrollingText'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ColorPickerField), findsNWidgets(3));
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Font weight'),
        findsOneWidget,
      );

      // 'name' is required (validator: "Enter a name") -- unrelated to what
      // this test is checking, but save() silently no-ops without it.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Settings name'),
        'Main ticker',
      );

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Font weight'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bold').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Bold'),
        findsOneWidget,
        reason: 'the dropdown itself must now show Bold as selected',
      );

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final saved = store
          .entries('settings')
          .where((e) => e.id == 'scrollingText')
          .firstOrNull;
      expect(
        saved?.number('fontWeight', 0),
        700.0,
        reason:
            'picking "Bold" must save the real numeric weight, not get lost',
      );
    },
  );

  test("comparing a saved value with a form value never throws on non-JSON values (editing a promotion with a start date)", () {
    final saved = DateTime.utc(2026, 10, 24, 5, 30);
    expect(sameFieldValue(saved, saved.toIso8601String()), isTrue);
    expect(sameFieldValue(saved, "2026-10-25T00:00:00.000Z"), isFalse);
    expect(sameFieldValue(Object(), "x"), isFalse);
    expect(sameFieldValue("a", "a"), isTrue);
    expect(sameFieldValue({"k": 1}, {"k": 1}), isTrue);
    expect(sameFieldValue(["a"], ["b"]), isFalse);
  });
}
