import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/shared.dart';

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

  testWidgets('Business profile opens without crashing when defaultPaymentMethod is unset (demo data)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    // The demo business entry never sets defaultPaymentMethod, which used to
    // crash the dropdown with an assertion error (no item matched the '' the
    // widget fell back to).
    expect(
      store.entries('settings').firstWhere((e) => e.id == 'business').text('defaultPaymentMethod'),
      '',
    );
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.scrollUntilVisible(
      find.text('Business profile'),
      100,
      scrollable: find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.right,
          )
          .first,
    );
    await tester.tap(find.text('Business profile'));
    await tester.pump();
    await tester.tap(find.text('Local Market'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.textContaining('Default payment'),
      300,
      scrollable: formScrollable,
    );
    expect(
      find.widgetWithText(
        DropdownButtonFormField<String>,
        'Default payment (direct_vendor / cash_on_delivery / platform_collected)',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a dropdown field with a stale stored value shows unselected instead of crashing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryEditor(
          store: store,
          collection: 'settings',
          // 'legacy_manual_invoice' was never one of the three fixed options and
          // no longer exists in the schema; it must not crash the form.
          entry: const Entry('business', {
            'name': 'Local Market',
            'defaultPaymentMethod': 'legacy_manual_invoice',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.textContaining('Default payment'),
      300,
      scrollable: formScrollable,
    );
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.widgetWithText(
        DropdownButtonFormField<String>,
        'Default payment (direct_vendor / cash_on_delivery / platform_collected)',
      ),
    );
    expect(dropdown.initialValue, isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Scrolling Text form opens without crashing on a blank noticeType/playback/direction (bug 2)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryEditor(
          store: store,
          collection: 'scrollingText',
          // A brand-new (or pre-existing, never-configured) scrolling text
          // entry leaves noticeType/playback unset (no built-in default,
          // unlike direction which safely defaults to 'rtl'), which used to
          // crash with the same DropdownMenuItem assertion as bug 1.
          entry: const Entry('scrollingText', {'name': 'Scrolling text'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    // Must match the field's top-to-bottom order in the form: scrollUntilVisible only scrolls forward.
    for (final MapEntry(key: label, value: expected) in {
      'Scroll direction (rtl / ltr)': 'rtl', // has a built-in safe default
      'Notice type': null, // genuinely unset — this is the crash scenario
      'Playback (running / stopped / paused)': null, // genuinely unset — this is the crash scenario
    }.entries) {
      await tester.scrollUntilVisible(find.textContaining(label), 300, scrollable: formScrollable);
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.widgetWithText(DropdownButtonFormField<String>, label),
      );
      expect(dropdown.initialValue, expected, reason: label);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('page view lets an admin resize a section without touching the old chip-list nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.pump();
    // The original chip-list navigation is still the default view.
    expect(find.text('Products & services'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to page view (click a section to edit it)'));
    await tester.pump();
    final categoriesTitle = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'Categories' && w.style?.fontWeight == FontWeight.bold,
    );
    expect(categoriesTitle, findsOneWidget);
    expect(
      sectionConfig(store.entries('settings'), 'categories').number('height', 0),
      0,
    );

    final categoriesCard = find.ancestor(of: categoriesTitle, matching: find.byType(Card));
    final increase = find.descendant(
      of: categoriesCard,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    await tester.tap(increase);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'categories').number('height', 0),
      240,
    );

    await tester.tap(increase);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'categories').number('height', 0),
      280,
    );

    final reset = find.descendant(
      of: categoriesCard,
      matching: find.byIcon(Icons.settings_backup_restore),
    );
    await tester.tap(reset);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'categories').number('height', 0),
      0,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('page view lets an admin drag a section into a new top-down order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.pump();
    await tester.tap(find.byTooltip('Switch to page view (click a section to edit it)'));
    await tester.pump();

    final settings = store.entries('settings');
    expect(
      sectionOrder(settings, 'popular') > sectionOrder(settings, 'categories'),
      isTrue,
      reason: 'Products starts below Categories by default',
    );

    // Drag the last handle (Products) up above the first one (Scrolling notice).
    final handles = find.byIcon(Icons.drag_indicator);
    await tester.ensureVisible(handles.last);
    await tester.pump();
    await tester.drag(handles.last, const Offset(0, -600));
    await tester.pumpAndSettle();

    final reordered = store.entries('settings');
    expect(
      sectionOrder(reordered, 'popular') < sectionOrder(settings, 'popular'),
      isTrue,
      reason: 'Dragging the Products handle upward should move it earlier than its original last place',
    );
    expect(
      sectionOrder(reordered, 'popular') < sectionOrder(reordered, 'categories'),
      isTrue,
      reason: 'Products should now sit above Categories',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
