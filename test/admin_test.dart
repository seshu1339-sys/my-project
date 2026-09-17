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

  testWidgets('admin can add a product with category, shop and price', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.tap(find.text('Add new'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final formScrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Organic Honey',
    );
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fresh & daily').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Corner Store').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Base price'),
      200,
      scrollable: formScrollable,
    );
    await tester.enterText(
      find.ancestor(
        of: find.textContaining('Base price'),
        matching: find.byType(TextFormField),
      ),
      '399',
    );
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      250,
      scrollable: formScrollable,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final saved = store
        .entries('products')
        .where((e) => e.text('name') == 'Organic Honey')
        .toList();
    expect(saved, hasLength(1));
    expect(saved.single.text('categoryId'), 'c0');
    expect(saved.single.text('shopId'), 's1');
    expect(saved.single.number('price'), 399);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
