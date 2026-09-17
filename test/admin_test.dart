import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin.dart';

void main() {
  testWidgets('admin can add and persist a category through the form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.tap(find.text('Categories'));
    await tester.pump();
    await tester.tap(find.text('Add new'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category name'),
      'Garden',
    );
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      250,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      store.entries('categories').where((e) => e.text('name') == 'Garden'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
