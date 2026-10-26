import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/fresh_strip.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/ui/admin_fresh_strip.dart';
import 'package:ecommerce_app/ui/home_category_product_strip.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:ecommerce_app/ui/shared.dart';

void main() {
  const products = [
    Entry('t1', {'name': 'Tomato', 'price': 32, 'shopId': 'a', 'imageUrl': ''}),
    Entry('t2', {'name': 'tomato', 'price': 28, 'shopId': 'b'}),
    Entry('o1', {'name': 'Onion', 'price': 40, 'shopId': 'a', 'imageUrl': 'http://x/onion.png'}),
    Entry('s1', {'name': 'Tomato repair', 'kind': 'service', 'price': 99}),
  ];

  test('the strip follows the admin\'s order, each item at its lowest price, with the item\'s photo; unsold items are left out', () {
    final record = const Entry('freshStrip', {
      'items': [
        {'name': 'Onion', 'productId': 'o1', 'imageUrl': 'http://x/onion.png'},
        {'name': 'Tomato', 'productId': 't1', 'imageUrl': 'http://x/tomato.png'},
        {'name': 'Mango', 'productId': 'm1'},
        {'name': ''},
      ],
    });
    final items = freshStripItems(record);
    expect(items.map((i) => i.name), ['Onion', 'Tomato', 'Mango']);
    final cards = freshStripProducts(items, products, '');
    expect(cards.map((c) => c.id), ['o1', 't2'], reason: 'the cheaper tomato; mango is not sold here');
    expect(cards[1].text('imageUrl'), 'http://x/tomato.png', reason: 'the item\'s photo when the product has none');
    expect(freshStripItems(null), isEmpty);
    expect(pagesOf(List.generate(20, (i) => i)).map((p) => p.length), [9, 9, 2]);
    // what the admin can add: one per item, with a photo where any shop has one, never a service
    final picks = itemPicks(products, 'to');
    expect(picks.map((p) => p.name), ['Tomato']);
    expect(itemPicks(products, 'on').single.imageUrl, 'http://x/onion.png');
  });

  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  List<Entry> many(int n) => [for (var i = 1; i <= n; i++) Entry('p$i', {'name': 'Item $i', 'price': 10 + i, 'unit': '1 kg'})];

  testWidgets('9 at a time, then the next 9, then the rest, then round again', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await openStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => HomeCategoryProductStrip(
            layout: layoutFor(context, store.entries('settings'), 'crossSellStrip'),
            defaultTitle: 'Fresh Fruits & Vegetables',
            icon: Icons.eco_outlined,
            products: many(20),
            store: store,
            onProduct: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    Iterable<String> shown() => tester.widgetList<Text>(find.textContaining(RegExp(r'^Item \d+$'))).map((t) => t.data!);
    expect(shown(), [for (var i = 1; i <= 9; i++) 'Item $i']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(shown(), [for (var i = 10; i <= 18; i++) 'Item $i']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(shown(), ['Item 19', 'Item 20']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(shown().first, 'Item 1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('on a phone: 3 a row, and the photos are not small', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await openStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => HomeCategoryProductStrip(
            layout: layoutFor(context, store.entries('settings'), 'crossSellStrip'),
            defaultTitle: 'Fresh Fruits & Vegetables',
            icon: Icons.eco_outlined,
            products: many(9),
            store: store,
            onProduct: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    final arts = tester.widgetList<ProductArt>(find.byType(ProductArt)).toList();
    expect(arts, hasLength(9));
    expect(arts.map((a) => a.height).toSet(), hasLength(1), reason: 'the same size on every card');
    expect(arts.first.height, greaterThan(65));
    final first = tester.getTopLeft(find.text('Item 1')), fourth = tester.getTopLeft(find.text('Item 4'));
    expect(fourth.dy, greaterThan(first.dy), reason: 'the 4th starts the second row');
    expect(find.byType(SingleChildScrollView), findsNothing, reason: 'all 9 fit, nothing to scroll sideways');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the admin types an item, it is added with its photo, numbered; move it up, take it out', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await openStore();
    store.catalog['products'] = [...products];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminFreshStripPage(store: store))));
    List<String> saved() => freshStripItems(store.entries('settings').where((e) => e.id == 'freshStrip').firstOrNull).map((i) => i.name).toList();

    await tester.enterText(find.byKey(const ValueKey('fresh-search')), 'tom');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fresh-pick-tomato')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fresh-search')), 'onion');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved(), ['Tomato', 'Onion']);
    expect(freshStripItems(store.entries('settings').firstWhere((e) => e.id == 'freshStrip'))[1].imageUrl, 'http://x/onion.png');
    expect(find.descendant(of: find.byKey(const ValueKey('fresh-item-onion')), matching: find.text('2')), findsOneWidget);

    // adding it again does nothing
    await tester.enterText(find.byKey(const ValueKey('fresh-search')), 'onion');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved(), ['Tomato', 'Onion']);

    await tester.tap(find.byKey(const ValueKey('fresh-up-onion')));
    await tester.pumpAndSettle();
    expect(saved(), ['Onion', 'Tomato']);
    await tester.tap(find.byKey(const ValueKey('fresh-remove-onion')));
    await tester.pumpAndSettle();
    expect(saved(), ['Tomato']);
  });
}
