import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

  testWidgets('admin-set product search radius settings round-trip onto settings/business', (
    tester,
  ) async {
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

    for (final MapEntry(key: label, value: value) in {
      'Product search radius presets, km (comma-separated, e.g. 2,5,10,25,50)': '1,3,7',
      'Default product search radius (km)': '3',
      'Maximum product search radius (km)': '7',
    }.entries) {
      await tester.scrollUntilVisible(find.text(label), 300, scrollable: formScrollable);
      await tester.enterText(find.widgetWithText(TextFormField, label), value);
    }
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.business.text('searchRadiusPresetsKm'), '1,3,7');
    expect(store.business.number('searchRadiusDefaultKm'), 3);
    expect(store.business.number('searchRadiusMaxKm'), 7);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('picking a rectangle target area zeroes the old circle fields and saves the shape', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    const original = Entry('promo1', {
      'name': 'Circle ad',
      'placement': 'carousel',
      'targetLatitude': 12.9,
      'targetLongitude': 77.5,
      'targetRadiusKm': 10,
    });
    await tester.pumpWidget(
      MaterialApp(home: EntryEditor(store: store, collection: 'promotions', entry: original)),
    );
    await tester.pumpAndSettle();
    final formScrollable = find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .first;

    await tester.scrollUntilVisible(find.text('Choose area on map'), 300, scrollable: formScrollable);
    expect(find.textContaining('Circle: 10 km'), findsOneWidget);
    await tester.tap(find.text('Choose area on map'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rectangle'));
    await tester.pump();
    final mapFinder = find.byType(FlutterMap);
    final topLeft = tester.getTopLeft(mapFinder);
    final mapSize = tester.getSize(mapFinder);
    // flutter_map briefly holds a tap to see if it becomes a double-tap
    // (zoom) gesture; the test must wait that out before the resulting
    // onTap callback fires. The second point avoids the bottom-right corner,
    // where the map's OpenStreetMap attribution control intercepts taps.
    await tester.tapAt(topLeft + const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(topLeft + Offset(mapSize.width - 20, mapSize.height / 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rectangle area set'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final saved = store.entries('promotions').firstWhere((e) => e.id == 'promo1');
    expect(saved.data['geoShape'], 'rectangle');
    expect(saved.data['targetRectangle'], isA<Map>());
    expect(saved.number('targetLatitude'), 0);
    expect(saved.number('targetLongitude'), 0);
    expect(saved.number('targetRadiusKm'), 0);
    expect(saved.data.containsKey('targetPolygon'), isFalse);
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
    const original = Entry('promo2', {
      'name': 'Polygon ad',
      'placement': 'carousel',
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
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(store.business.text('websiteUrl'), '', reason: 'a non-HTTPS website must not save');

    await tester.scrollUntilVisible(find.text(emailLabel), -300, scrollable: formScrollable);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, websiteLabel), 'https://locamarket.in');
    await tester.scrollUntilVisible(find.text('Save changes'), 300, scrollable: formScrollable);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.business.text('supportEmail'), 'support@locamarket.in');
    expect(store.business.text('websiteUrl'), 'https://locamarket.in');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('vendor and field-staff photo limits default to 2 and save independently of each other', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    const vendorLabel = 'Vendor shop photo limit (1-9, default 2)';
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
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, vendorLabel)).controller!.text, '2');
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
