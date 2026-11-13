import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/home_section_config.dart';
import 'package:ecommerce_app/ui/admin_groups.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';

// The studio opens on Insights; the other pages are tabs, and everything else is a section of the Settings tab.
Future<void> goTab(WidgetTester tester, int index) async {
  DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(index);
  await tester.pumpAndSettle();
}

Future<void> goSettings(WidgetTester tester, String key) async {
  await goTab(tester, DefaultTabController.of(tester.element(find.byType(TabBar).first)).length - 1); // Settings is the last tab
  // The Settings index lists every section under the six group names; scroll to the section first.
  final tile = find.byKey(ValueKey('settings-$key'));
  await tester.scrollUntilVisible(tile, 200, scrollable: find.descendant(of: find.byType(AdminSettingsPage), matching: find.byType(Scrollable)).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// Opens one page of one of the six groups (lib/ui/admin_groups.dart).
Future<void> goItem(WidgetTester tester, String group, String item) async {
  await goTab(tester, adminGroups.indexWhere((g) => g.id == group));
  await tester.tap(find.byKey(ValueKey('group-item-$item')));
  await tester.pumpAndSettle();
}

Future<void> openPageView(WidgetTester tester) async {
  await goSettings(tester, 'layout');
  await tester.tap(find.byKey(const ValueKey('layout-page-view')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin can add and persist a category through the form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await goSettings(tester, 'categories');
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
    // The category form has the "Own photo required" switch too: scroll the form to its end so Save is fully in view.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
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
    await goItem(tester, 'vendors', 'Products');
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
    await goSettings(tester, 'settings'); // Business Profile
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

  testWidgets('page view (Settings > Layout) lets an admin resize a section', (
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
    await openPageView(tester);
    final sectionTitle = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'Products & services' && w.style?.fontWeight == FontWeight.bold,
    );
    expect(sectionTitle, findsOneWidget);
    expect(
      sectionConfig(store.entries('settings'), 'popular').number('height', 0),
      0,
    );

    final sectionCard = find.ancestor(of: sectionTitle, matching: find.byType(Card));
    final increase = find.descendant(
      of: sectionCard,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    await tester.tap(increase);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'popular').number('height', 0),
      240,
    );

    await tester.tap(increase);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'popular').number('height', 0),
      280,
    );

    final reset = find.descendant(
      of: sectionCard,
      matching: find.byIcon(Icons.settings_backup_restore),
    );
    await tester.tap(reset);
    await tester.pump();
    expect(
      sectionConfig(store.entries('settings'), 'popular').number('height', 0),
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
    await openPageView(tester);

    final settings = store.entries('settings');
    expect(
      sectionOrder(settings, 'localServices') > sectionOrder(settings, 'categories'),
      isTrue,
      reason: 'Local Services starts below Categories by default',
    );

    // Drag the last handle (Local Services) up above the first one (Scrolling notice).
    final handles = find.byIcon(Icons.drag_indicator);
    await tester.ensureVisible(handles.last);
    await tester.pump();
    await tester.drag(handles.last, const Offset(0, -600));
    await tester.pumpAndSettle();

    final reordered = store.entries('settings');
    expect(
      sectionOrder(reordered, 'localServices') < sectionOrder(settings, 'localServices'),
      isTrue,
      reason: 'Dragging the Local Services handle upward should move it earlier than its original last place',
    );
    expect(
      sectionOrder(reordered, 'localServices') < sectionOrder(reordered, 'categories'),
      isTrue,
      reason: 'Local Services should now sit above Categories',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Business Profile has ONE km for what customers see, first in the form; no separate search radius', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(
      MaterialApp(home: EntryEditor(store: store, collection: 'settings', entry: null)),
    );
    await tester.pumpAndSettle();
    const label = 'Customers see shops, offers and products within (km)';
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(find.widgetWithText(TextFormField, label), findsOneWidget);
    expect(identical(fields.first, tester.widget(find.widgetWithText(TextFormField, label))), isTrue, reason: 'the first field');
    expect(find.textContaining('search radius'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, label), '15');
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(store.business.number('radiusKm'), 15);
    expect(store.reachKm, 15);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('editing an unrelated field on a shape-targeted promotion leaves its shape data untouched', (
    tester,
  ) async {
    // Store.save() does a full, non-merge overwrite: this is the direct
    // regression test for that hazard, proving EntryEditor's `{...?entry?.data}`
    // spread really does carry forward geo-shape fields the picker was never
    // reopened for.
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['shops'] = [const Entry('shop-1', {'name': 'Suma Fresh Mart', 'latitude': 12.95, 'longitude': 77.6})];
    const original = Entry('promo2', {
      'name': 'Polygon ad',
      'placement': 'carousel',
      'radiusShopId': 'shop-1',
      'geoShape': 'polygon',
      'targetPolygon': [
        {'lat': 12.90, 'lng': 77.50},
        {'lat': 13.00, 'lng': 77.50},
        {'lat': 12.95, 'lng': 77.70},
      ],
    });
    await store.save('promotions', original);
    await tester.pumpWidget(
      MaterialApp(home: EntryEditor(store: store, collection: 'promotions', entry: original)),
    );
    await tester.pumpAndSettle();
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;

    // Never touches "Choose area on map" — only an unrelated field changes.
    await tester.enterText(find.widgetWithText(TextFormField, 'Headline / ticker text'), 'Polygon ad (updated)');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    // The form gained a Location field, so the button can sit just under the fold.
    await tester.drag(formScrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final saved = store.entries('promotions').firstWhere((e) => e.id == 'promo2');
    expect(saved.text('name'), 'Polygon ad (updated)');
    expect(saved.data['geoShape'], 'polygon');
    expect(parsePolygonField(saved.data['targetPolygon']), isNotNull);
    expect(parsePolygonField(saved.data['targetPolygon'])!.length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('public support email and website save, and reject invalid values', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(
      MaterialApp(home: EntryEditor(store: store, collection: 'settings', entry: null)),
    );
    await tester.pumpAndSettle();
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    final emailLabel = 'Public support email (shown to everyone — never your personal inbox)';
    const websiteLabel = 'Website URL';

    // A fresh business profile already defaults to the public support
    // contact, never the operator's personal inbox. The website field sits
    // right below it, so scrolling to email also brings it into the tree —
    // one extra pump lets the newly-built sibling register with find.text.
    await tester.scrollUntilVisible(find.text(emailLabel), 300, scrollable: formScrollable);
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, emailLabel)).controller!.text, 'info@locamarket.in');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, websiteLabel)).controller!.text, 'https://locamarket.in');

    // Bad values must not save — checked via store state (not the inline
    // validator text, which scrolls out of the tree once "Save changes" is
    // brought into view further down the same lazily-built list).
    await tester.enterText(find.widgetWithText(TextFormField, emailLabel), 'not-an-email');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(store.business.text('supportEmail'), '', reason: 'invalid email must not save');

    // Scroll back up (negative delta) to reach the email field again, since
    // "Save changes" is further down the same list.
    await tester.scrollUntilVisible(find.text(emailLabel), -300, scrollable: formScrollable);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, emailLabel), 'support@locamarket.in');
    await tester.enterText(find.widgetWithText(TextFormField, websiteLabel), 'http://locamarket.in');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(store.business.text('websiteUrl'), '', reason: 'a non-HTTPS website must not save');

    await tester.scrollUntilVisible(find.text(emailLabel), -300, scrollable: formScrollable);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, websiteLabel), 'https://locamarket.in');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.business.text('supportEmail'), 'support@locamarket.in');
    expect(store.business.text('websiteUrl'), 'https://locamarket.in');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('vendor photo limit defaults to 3, field-staff to 2, and they save independently of each other', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    const vendorLabel = 'Vendor shop photo limit (1-9, default 3; photo 1 is the shop, required)';
    const fieldLabel = 'Field Assistant item photo limit (1-9, default 2)';
    // A real underlying page beneath EntryEditor (like AdminPage in the real
    // app) so a successful save's Navigator.pop() returns to it instead of
    // emptying the Navigator's history — needed here because this test opens
    // EntryEditor twice in a row, unlike every other single-save test above.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    Future<void> openEditor(Entry? entry) async {
      navigator.push(MaterialPageRoute<void>(builder: (_) => EntryEditor(store: store, collection: 'settings', entry: entry)));
      await tester.pumpAndSettle();
    }

    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;

    await openEditor(null);
    // A fresh business profile already defaults both limits to 2, preserving
    // the app's existing (previously hardcoded) vendor shop-photo behavior.
    await tester.scrollUntilVisible(find.text(vendorLabel), 300, scrollable: formScrollable);
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, vendorLabel)).controller!.text, '3');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, fieldLabel)).controller!.text, '2');

    // Changing only the vendor limit must never touch the field-staff one.
    await tester.enterText(find.widgetWithText(TextFormField, vendorLabel), '5');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.business.number('vendorPhotoLimit'), 5);
    expect(store.business.number('fieldPhotoLimit'), 2, reason: 'changing the vendor limit must not affect the field-staff limit');

    // Re-open the now-saved business profile for a second, independent edit —
    // mirrors a real admin navigating back in to change one more setting.
    await openEditor(Entry('business', store.business.data));
    await tester.scrollUntilVisible(find.text(vendorLabel), 300, scrollable: formScrollable);
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, vendorLabel)).controller!.text, '5', reason: 'the vendor limit saved above is carried into this fresh edit');
    await tester.scrollUntilVisible(find.text(fieldLabel), 300, scrollable: formScrollable);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, fieldLabel), '3');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.ensureVisible(find.text('Save changes'));
    // The first save's "Saved" message sits over the bottom of the form for a few seconds: let it go first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.business.number('fieldPhotoLimit'), 3);
    expect(store.business.number('vendorPhotoLimit'), 5, reason: 'changing the field-staff limit must not affect the vendor limit');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('an out-of-range photo limit is rejected and does not save', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(
      MaterialApp(home: EntryEditor(store: store, collection: 'settings', entry: null)),
    );
    await tester.pumpAndSettle();
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;
    const fieldLabel = 'Field Assistant item photo limit (1-9, default 2)';

    await tester.scrollUntilVisible(find.text(fieldLabel), 300, scrollable: formScrollable);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, fieldLabel), '15');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(store.business.number('fieldPhotoLimit'), 0, reason: 'nothing saved yet — a fresh business profile has no stored value at all');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
