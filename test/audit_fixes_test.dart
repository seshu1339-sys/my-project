// Regression tests for the project-wide audit: the Visual Editor's #14, an editor
// that overwrote fields changed meanwhile, free (price 0) products, UTC times in
// the offer form, and the admin list's location / schedule / problem labels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_fields.dart';
import 'package:ecommerce_app/ui/admin_list_labels.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';
import 'package:ecommerce_app/ui/visual_editor.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _save(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Save changes'),
    300,
    scrollable: find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first,
  );
  await tester.tap(find.text('Save changes'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('#14 ticker marquee', () {
    test('the Visual Editor opens the Scrolling Text form for it, which has the font size', () {
      expect(externalEditorForm('tickerMarquee'), 'scrollingText');
      expect(externalEditorForm('logo'), isNull);
      expect(fields['scrollingText']!.keys, containsAll(['fontSize', 'fontWeight', 'fontFamily', 'textColor', 'speed']));
    });

    testWidgets('its font size saves to the ticker document and nothing from the Business Profile leaks in', (tester) async {
      await _tall(tester);
      final store = await _store();
      final ticker = store.entries('settings').firstWhere((e) => e.id == 'scrollingText');
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'scrollingText', entry: ticker)));
      await tester.pump();
      final size = find.widgetWithText(TextFormField, 'Font size');
      await tester.ensureVisible(size);
      await tester.enterText(size, '22');
      await _save(tester);
      final saved = store.entries('settings').firstWhere((e) => e.id == 'scrollingText');
      expect(saved.number('fontSize'), 22);
      expect(saved.data.containsKey('tagline'), isFalse);
      expect(saved.data.containsKey('address'), isFalse);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('editing a product', () {
    testWidgets('saving an unrelated change keeps the stock an order changed meanwhile', (tester) async {
      await _tall(tester);
      final store = await _store();
      await store.save('products', const Entry('p1', {'name': 'Rice', 'price': 50, 'stock': 5, 'categoryId': 'c0', 'shopId': 's1', 'active': true, 'unit': 'kg'}));
      final opened = store.entries('products').firstWhere((e) => e.id == 'p1'); // the admin opens it
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'products', entry: opened)));
      await tester.pump();
      // An order and a review change the document while the form is open.
      await store.updateFields('products', 'p1', {'stock': 2, 'avgRating': 4.5, 'reviewCount': 3});
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Basmati rice');
      await _save(tester);
      final saved = store.entries('products').firstWhere((e) => e.id == 'p1');
      expect(saved.text('name'), 'Basmati rice');
      expect(saved.number('stock'), 2, reason: 'the order\'s stock change must survive');
      expect(saved.number('avgRating'), 4.5);
      expect(saved.number('reviewCount'), 3);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('the admin\'s own stock change is still saved', (tester) async {
      await _tall(tester);
      final store = await _store();
      await store.save('products', const Entry('p1', {'name': 'Rice', 'price': 50, 'stock': 5, 'categoryId': 'c0', 'shopId': 's1', 'active': true}));
      final opened = store.entries('products').firstWhere((e) => e.id == 'p1');
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'products', entry: opened)));
      await tester.pump();
      final stock = find.widgetWithText(TextFormField, 'Available quantity / booking slots');
      await tester.ensureVisible(stock);
      await tester.enterText(stock, '40');
      await _save(tester);
      expect(store.entries('products').firstWhere((e) => e.id == 'p1').number('stock'), 40);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('a product cannot be saved free (blank or 0 price)', (tester) async {
      await _tall(tester);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'products')));
      await tester.pump();
      final price = find.widgetWithText(TextFormField, 'Base price (₹)');
      expect(tester.widget<TextFormField>(price).controller!.text, isEmpty, reason: 'a new product no longer starts at 0');
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Free thing');
      await tester.ensureVisible(price);
      for (final bad in ['', '0']) {
        await tester.enterText(price, bad);
        await _save(tester);
        expect(store.entries('products').where((e) => e.text('name') == 'Free thing'), isEmpty, reason: 'price "$bad" must not save');
        expect(find.text('Enter a price above 0'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('offer dates', () {
    testWidgets('are shown in local time and saved back as the same moment', (tester) async {
      await _tall(tester);
      final store = await _store();
      final utc = DateTime.utc(2026, 11, 1, 4, 30);
      await store.save('promotions', Entry('o1', {'name': 'Diwali', 'placement': 'carousel', 'active': true, 'endsAt': utc.toIso8601String()}));
      final opened = store.entries('promotions').firstWhere((e) => e.id == 'o1');
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'promotions', entry: opened)));
      await tester.pump();
      final field = find.widgetWithText(TextFormField, 'Ends at (optional)');
      await tester.ensureVisible(field);
      final shown = tester.widget<TextFormField>(field).controller!.text;
      expect(shown.endsWith('Z'), isFalse, reason: 'shown as local time, not UTC');
      expect(DateTime.parse(shown), utc.toLocal());
      await _save(tester);
      expect(DateTime.parse(store.entries('promotions').firstWhere((e) => e.id == 'o1').text('endsAt')), utc);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('admin list labels', () {
    final now = DateTime.utc(2026, 11, 10);
    test('a promotion says where it shows and whether it is live', () {
      expect(promotionLocationLabel(const Entry('a', {})), 'All towns');
      expect(
        promotionLocationLabel(const Entry('a', {'locations': 'Rajahmundry (East Godavari), district:Krishna, state:Telangana'})),
        'Rajahmundry (East Godavari), All of Krishna district, All of Telangana',
      );
      Entry p(Map<String, dynamic> data) => Entry('a', data);
      expect(promotionStatusLabel(p({}), now: now), 'Live');
      expect(promotionStatusLabel(p({'active': false}), now: now), 'Hidden');
      expect(promotionStatusLabel(p({'endsAt': '2026-11-01T00:00:00Z'}), now: now), 'Expired');
      expect(promotionStatusLabel(p({'startsAt': '2026-12-01T00:00:00Z'}), now: now), 'Scheduled');
      expect(promotionStatusLabel(p({'startsAt': '2026-11-01T00:00:00Z', 'endsAt': '2026-12-01T00:00:00Z'}), now: now), 'Live');
    });

    test('a product lists what is missing', () {
      const complete = Entry('p', {'imageUrl': 'https://x/y.png', 'categoryId': 'c', 'shopId': 's', 'price': 10, 'stock': 3});
      expect(productProblems(complete), isEmpty);
      expect(productProblems(const Entry('p', {'price': 0, 'stock': 0}), categoryIds: {'c'}, shopIds: {'s'}),
          ['No photo', 'No category', 'No shop', 'Price is 0', 'Out of stock']);
      expect(productProblems(const Entry('p', {'imageUrl': 'u', 'categoryId': 'gone', 'shopId': 's', 'price': 1, 'stock': 1}), categoryIds: {'c'}, shopIds: {'s'}),
          ['No category']);
      expect(productProblems(const Entry('p', {'imageUrl': 'u', 'categoryId': 'c', 'kind': 'service', 'price': 1, 'stock': 1})), isEmpty,
          reason: 'a service needs no shop');
    });
  });
}
