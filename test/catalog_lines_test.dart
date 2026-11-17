import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/catalog_lines.dart';
import 'package:ecommerce_app/ui/home_catalog_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Category lines under Today's Offers (owner, 16 Nov 2026).
void main() {
  final categories = [
    Entry('cat-fruits', {'name': 'Fruits'}),
    Entry('cat-veg', {'name': 'Fresh & Vegetables'}),
    Entry('cat-fancy', {'name': 'Fancy'}),
    Entry('cat-plastic', {'name': 'Plastics'}),
  ];

  test('settings: defaults 5 s / 3 lines / 3 (app) / 6 (website); 3 to 30 seconds; saved order', () {
    final d = CatalogLinesConfig.from(const []);
    expect([d.seconds, d.lines, d.itemsApp, d.itemsWeb], [5, 3, 3, 6]);
    final c = CatalogLinesConfig.from([Entry('androidHome', {'lineSeconds': 12, 'lineCount': 2, 'lineItems': 4, 'lineItemsWeb': 7, 'lineCategoryOrder': 'cat-fancy,cat-fruits'})]);
    expect([c.seconds, c.lines, c.itemsApp, c.itemsWeb, c.order], [12, 2, 4, 7, ['cat-fancy', 'cat-fruits']]);
    expect(CatalogLinesConfig.from([Entry('androidHome', {'lineSeconds': 2})]).seconds, 5, reason: 'under 3 s: the default');
    expect(CatalogLinesConfig.from([Entry('androidHome', {'lineSeconds': 31})]).seconds, 5);
    expect(CatalogLinesConfig.from([Entry('androidHome', c.toFields())]).toFields(), c.toFields());
  });

  test('items: the Item Catalog first, then the photos inside the app; one category per line; an empty category is left out', () {
    final items = catalogLineItems(categories: categories, library: [
      Entry('lib-1', {'name': 'Banana', 'categoryId': 'cat-fruits', 'imageUrl': 'https://x/banana.jpg'}),
      Entry('lib-2', {'name': 'Off item', 'categoryId': 'cat-fruits', 'imageUrl': 'https://x/off.jpg', 'active': false}),
    ]);
    expect(items['cat-fruits']!.first.libraryItemId, 'lib-1');
    expect(items['cat-fruits']!.where((i) => i.name == 'Off item'), isEmpty);
    expect(items['cat-fruits']!.length, greaterThan(10), reason: 'the app has 20 fruit photos');
    expect(items['cat-fancy']!.length, 8);
    expect(items['cat-plastic'], isNull, reason: 'no photos: no line');
    for (final list in items.values) {
      expect(list.map((i) => i.name.toLowerCase()).toSet().length, list.length, reason: 'no item twice in a category');
      expect(list.map((i) => i.categoryId).toSet().length, 1);
    }
    expect(catalogLineOrder(items, categories, ['cat-fancy']), ['cat-fancy', 'cat-fruits', 'cat-veg']);
  });

  test('price: the lowest in the area per kg; none -> null', () {
    const item = CatalogLineItem(id: 'a', name: 'Tomato', categoryId: 'cat-veg');
    final products = [
      Entry('p1', {'name': 'Tomato', 'price': 40, 'unit': '1 kg'}),
      Entry('p2', {'name': ' tomato ', 'price': 70, 'unit': '2 kg'}),
      Entry('p3', {'name': 'Onion', 'price': 10, 'unit': '1 kg'}),
    ];
    final best = lowestLinePrice(item, products)!;
    expect([best.product.id, best.price, best.unit], ['p2', 70, '2 kg']);
    expect(lowestLinePrice(const CatalogLineItem(id: 'b', name: 'Mango', categoryId: 'cat-fruits'), products), isNull);
  });

  test('rotation: a coming-back category shows its NEXT items, all of them before starting again; never twice on the screen', () {
    final r = CatalogLineRotation(lines: 2, perLine: 3)..update(['a', 'b', 'c'], {'a': 7, 'b': 3, 'c': 2});
    expect([for (final s in r.shown) s.categoryId], ['a', 'b']);
    expect(r.shown[0].indexes, [0, 1, 2]);
    final seenA = <int>[...r.shown[0].indexes];
    for (var turn = 0; turn < 12; turn++) {
      r.next(turn % 2);
      final cats = [for (final s in r.shown) s.categoryId];
      expect(cats.toSet().length, cats.length, reason: 'two lines never show the same category');
      for (final s in r.shown) {
        expect(s.indexes.toSet().length, s.indexes.length, reason: 'no item twice in a line');
      }
      if (r.shown[turn % 2].categoryId == 'a') seenA.addAll(r.shown[turn % 2].indexes);
    }
    expect(seenA.take(7).toSet(), {0, 1, 2, 3, 4, 5, 6}, reason: 'every item of a category before any comes back');
    final c = r.shown.firstWhere((s) => s.categoryId == 'c', orElse: () => r.shown.first);
    if (c.categoryId == 'c') expect(c.indexes.length, 2, reason: 'a small category shows what it has');
  });

  test('rotation: as many categories as lines -> a line changes to the same category\'s next items', () {
    final r = CatalogLineRotation(lines: 3, perLine: 2)..update(['a', 'b'], {'a': 4, 'b': 4});
    expect(r.shown.length, 2, reason: 'two categories: two lines');
    r.next(0);
    expect([r.shown[0].categoryId, r.shown[0].indexes], ['a', [2, 3]]);
  });

  testWidgets('the lines show photos, names, the price or the exact "not updated" text, and change with no reads', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Store();
    store.catalog['categories'] = categories;
    store.catalog['settings'] = [Entry('androidHome', {'lineSeconds': 3, 'lineCount': 2})];
    store.catalog['productImageLibrary'] = [];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeCatalogLines(store: store, android: true, onProduct: (_) {})))));
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog-line-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-line-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-line-2')), findsNothing, reason: 'the admin chose 2 lines');
    expect(find.text(noLocalPriceText), findsNWidgets(6), reason: 'no vendor here: every box says so');
    final first = find.descendant(of: find.byKey(const ValueKey('catalog-line-0')), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join('|');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 700));
    final after = find.descendant(of: find.byKey(const ValueKey('catalog-line-0')), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join('|');
    expect(after, isNot(first), reason: 'line 1 changed after its turn');
    await tester.pumpWidget(const SizedBox());
  });
}
