import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/color_picker_field.dart';
import 'package:ecommerce_app/ui/group_item_design_form.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  void setRealisticSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'has no size field, and saving a design change never touches the item\'s own content fields',
    (tester) async {
      final store = await openStore();
      setRealisticSize(tester);
      await store.save(
        'categories',
        const Entry('catA', {
          'name': 'Vegetables',
          'imageUrl': 'https://example.com/veg.png',
          'parentId': '',
          'order': 5.0,
        }),
      );

      final key = GlobalKey<GroupItemDesignFormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupItemDesignForm(
                key: key,
                store: store,
                collection: 'categories',
                id: 'catA',
              ),
            ),
          ),
        ),
      );

      // Rule: sub-numbers have no size option at all.
      expect(find.widgetWithText(TextFormField, 'Width'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Height'), findsNothing);
      expect(
        find.byType(ColorPickerField),
        findsNWidgets(3),
        reason: 'background/text/border color pickers',
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Brightness (0.2 - 2, optional)'),
        '1.4',
      );
      await key.currentState!.save();

      final saved = store
          .entries('categories')
          .where((e) => e.id == 'catA')
          .first;
      expect(saved.number('brightness', 0), 1.4);
      // Content, untouched by a pure design-field change.
      expect(saved.text('name'), 'Vegetables');
      expect(saved.text('imageUrl'), 'https://example.com/veg.png');
      expect(saved.number('order', -1), 5.0);
    },
  );
}
