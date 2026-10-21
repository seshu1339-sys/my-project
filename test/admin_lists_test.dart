import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_entry_list.dart';
import 'package:ecommerce_app/ui/admin_list_labels.dart';

Entry _p(String id, String name, {String shop = '', String category = 'cat-fruits', int order = 1, bool active = true, String kind = 'product'}) => Entry(id, {
  'name': name, 'categoryId': category, 'shopId': shop, 'order': order, 'active': active, 'kind': kind,
  'price': 10, 'stock': 5, 'imageUrl': 'https://example.test/$id.jpg',
});

Future<Store> _store({List<Entry>? products, List<Entry>? promotions}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['categories'] = const [
    Entry('cat-fruits', {'name': 'Fruits', 'order': 1}),
    Entry('cat-veg', {'name': 'Vegetables', 'order': 2}),
    Entry('cat-care', {'name': 'Personal care', 'order': 3}),
  ];
  store.catalog['shops'] = const [
    Entry('shop-a', {'name': 'Local Bakery', 'order': 1}),
    Entry('shop-b', {'name': 'Ramu Kirana', 'order': 2}),
  ];
  store.catalog['products'] = [...?products];
  store.catalog['promotions'] = [...?promotions];
  return store;
}

Future<void> _show(WidgetTester tester, Store store, String section) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminEntryList(store: store, section: section))));
  await tester.pumpAndSettle();
}

int _order(Store store, String collection, String id) => store.entries(collection).firstWhere((e) => e.id == id).number('order').toInt();

void main() {
  group('helpers', () {
    test('a promotion\'s click action in words', () {
      String label(String target) => promotionTargetLabel(
        Entry('x', {'target': target}),
        categories: const {'cat-care': 'Personal care'},
        products: const {'p1': 'Apple'},
        shops: const {'s1': 'Local Bakery'},
      );
      expect(label('category:cat-care'), 'Category: Personal care');
      expect(label('category:cat-gone'), 'Category: cat-gone');
      expect(label('product:p1'), 'Product: Apple');
      expect(label('shop:s1'), 'Shop: Local Bakery');
      expect(label('shops'), 'Shops page');
      expect(label('services'), 'Services page');
      expect(label('https://example.test'), 'Link');
      expect(label(''), 'No click action');
    });

    test('records sort by order number, then name; equal numbers are untidy; renumbering writes only what is wrong', () {
      final list = sortedByOrder([_p('b', 'Banana', order: 1), _p('a', 'Apple', order: 1), _p('c', 'Cherry', order: 3)]);
      expect(list.map((e) => e.id), ['a', 'b', 'c']);
      expect(hasUntidyOrder(list), isTrue);
      expect(renumberChanges(list), {'b': {'order': 2}}, reason: 'a is already 1 and c is already 3');
      expect(renumberChanges(sortedByOrder([_p('a', 'A', order: 1), _p('b', 'B', order: 1), _p('c', 'C', order: 1)])), {'b': {'order': 2}, 'c': {'order': 3}});
      final tidy = sortedByOrder([_p('a', 'A', order: 1), _p('b', 'B', order: 2)]);
      expect(hasUntidyOrder(tidy), isFalse);
      expect(renumberChanges(tidy), isEmpty);
    });

    test('moving a row renumbers the list 1..n', () {
      final list = [_p('a', 'A', order: 1), _p('b', 'B', order: 2), _p('c', 'C', order: 3)];
      // Flutter's convention: moving index 0 below index 2 arrives as newIndex 3
      expect(reorderChanges(list, 0, 3), {'a': {'order': 3}, 'b': {'order': 1}, 'c': {'order': 2}});
      expect(reorderChanges(list, 2, 0), {'c': {'order': 1}, 'a': {'order': 2}, 'b': {'order': 3}});
      expect(reorderChanges(list, 1, 1), isEmpty);
    });

    test('updateMany changes only the named records and fields', () async {
      final store = await _store(products: [_p('a', 'A', order: 1), _p('b', 'B', order: 1)]);
      await store.updateMany('products', {'a': {'order': 2}, 'missing': {'order': 9}, 'b': {}});
      expect(_order(store, 'products', 'a'), 2);
      expect(_order(store, 'products', 'b'), 1);
      expect(store.entries('products').firstWhere((e) => e.id == 'a').text('name'), 'A');
      expect(store.entries('products').length, 2);
    });
  });

  group('products list', () {
    Future<Store> sample() => _store(products: [
      _p('prod-apple', 'Apple', shop: 'shop-a', category: 'cat-fruits', order: 1),
      _p('prod-banana', 'Banana', shop: '', category: 'cat-fruits', order: 1),
      _p('prod-carrot', 'Carrot', shop: 'shop-b', category: 'cat-veg', order: 1, active: false),
      _p('prod-soap', 'Soap', shop: '', category: 'cat-care', order: 1),
      _p('svc-plumber', 'Plumber', shop: '', category: 'cat-care', order: 1, kind: 'service'),
    ]);

    testWidgets('rows show names, category and shop but never the technical id', (tester) async {
      final store = await sample();
      await _show(tester, store, 'products');
      expect(find.text('Apple'), findsOneWidget);
      expect(find.textContaining('prod-apple'), findsNothing);
      expect(find.textContaining('prod-'), findsNothing);
      expect(find.textContaining('Fruits'), findsWidgets);
      expect(find.textContaining('Local Bakery'), findsOneWidget);
      expect(find.textContaining('• No shop •'), findsNWidgets(2), reason: 'Banana and Soap; a service needs no shop');
      expect(find.byKey(const ValueKey('list-count')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('list-count'))).data, '5 products');
    });

    testWidgets('search, "No shop only", category and Published/Draft narrow the list, and clearing restores it', (tester) async {
      final store = await sample();
      await _show(tester, store, 'products');
      String count() => tester.widget<Text>(find.byKey(const ValueKey('list-count'))).data!;
      await tester.enterText(find.byKey(const ValueKey('product-search')), 'ban');
      await tester.pumpAndSettle();
      expect(find.text('Banana'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(count(), '1 of 5 products');
      await tester.enterText(find.byKey(const ValueKey('product-search')), 'bakery'); // finds by shop name too
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('product-search')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('filter-no-shop')));
      await tester.pumpAndSettle();
      expect(find.text('Banana'), findsOneWidget);
      expect(find.text('Soap'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(find.text('Plumber'), findsNothing, reason: 'a service does not need a shop');
      expect(count(), '2 of 5 products');
      await tester.tap(find.byKey(const ValueKey('filter-no-shop')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('filter-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vegetables').last);
      await tester.pumpAndSettle();
      expect(find.text('Carrot'), findsOneWidget);
      expect(count(), '1 of 5 products');
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(count(), '5 products');

      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();
      expect(find.text('Carrot'), findsOneWidget);
      expect(count(), '1 of 5 products');
      await tester.tap(find.text('Published'));
      await tester.pumpAndSettle();
      expect(find.text('Carrot'), findsNothing);
      expect(count(), '4 of 5 products');
      await tester.enterText(find.byKey(const ValueKey('product-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches. Clear the search or filters.'), findsOneWidget);
    });

    testWidgets('bulk: select several products and assign them one shop', (tester) async {
      final store = await sample();
      await _show(tester, store, 'products');
      await tester.tap(find.byKey(const ValueKey('filter-no-shop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-select')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('assign-shop'))).onPressed, isNull, reason: 'nothing selected yet');
      await tester.tap(find.byKey(const ValueKey('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assign-shop')));
      await tester.pumpAndSettle();
      expect(find.text('Assign a shop to 2 products'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('assign-shop-confirm'))).onPressed, isNull, reason: 'choose a shop first');
      await tester.tap(find.byKey(const ValueKey('assign-shop-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ramu Kirana').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-shop-confirm')));
      await tester.pumpAndSettle();
      String shop(String id) => store.entries('products').firstWhere((e) => e.id == id).text('shopId');
      expect(shop('prod-banana'), 'shop-b');
      expect(shop('prod-soap'), 'shop-b');
      expect(shop('prod-apple'), 'shop-a', reason: 'untouched');
      expect(shop('svc-plumber'), '', reason: 'was not selected');
      expect(find.text('Banana'), findsNothing, reason: 'the No-shop filter no longer matches it');
    });

    testWidgets('equal order numbers are flagged; Renumber gives every product its own 1..n', (tester) async {
      final store = await sample();
      await _show(tester, store, 'products');
      expect(find.byKey(const ValueKey('untidy-order')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('renumber')));
      await tester.pumpAndSettle();
      final orders = store.entries('products').map((e) => e.number('order').toInt()).toList()..sort();
      expect(orders, [1, 2, 3, 4, 5]);
      expect(find.byKey(const ValueKey('untidy-order')), findsNothing);
    });

    testWidgets('dragging a row moves it and renumbers the list; dragging is off while a filter is on', (tester) async {
      final store = await _store(products: [_p('a', 'Apple', order: 1), _p('b', 'Banana', order: 2), _p('c', 'Carrot', order: 3)]);
      await _show(tester, store, 'products');
      expect(find.byKey(const ValueKey('untidy-order')), findsNothing, reason: 'already 1, 2, 3');
      final handles = find.byIcon(Icons.drag_indicator);
      expect(handles, findsNWidgets(3));
      await tester.drag(handles.last, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(_order(store, 'products', 'c'), 2);
      expect(_order(store, 'products', 'b'), 3);
      expect(_order(store, 'products', 'a'), 1);
      await tester.tap(find.byKey(const ValueKey('filter-no-shop')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });
  });

  group('promotions and categories', () {
    testWidgets('two promotions with the same headline are told apart by what they lead to', (tester) async {
      final store = await _store(promotions: const [
        Entry('p1', {'name': "Today's Offer", 'target': 'category:cat-care', 'order': 1, 'active': true, 'placement': 'carousel'}),
        Entry('p2', {'name': "Today's Offer", 'target': 'category:cat-veg', 'order': 2, 'active': true, 'placement': 'carousel'}),
        Entry('p3', {'name': "Today's Offer", 'target': 'shop:shop-a', 'order': 3, 'active': true, 'placement': 'ad'}),
      ]);
      await _show(tester, store, 'promotions');
      expect(find.text("Today's Offer — Category: Personal care"), findsOneWidget);
      expect(find.text("Today's Offer — Category: Vegetables"), findsOneWidget);
      expect(find.text("Today's Offer — Shop: Local Bakery"), findsOneWidget);
      expect(find.textContaining('Advertisement'), findsOneWidget);
      expect(find.textContaining('Banner'), findsNWidgets(2));
      expect(find.textContaining('p1'), findsNothing);
    });

    testWidgets('repeated promotion order numbers can be renumbered, and categories can be dragged', (tester) async {
      final store = await _store(promotions: const [
        Entry('p1', {'name': 'A', 'order': 1, 'active': true}),
        Entry('p2', {'name': 'B', 'order': 1, 'active': true}),
        Entry('p3', {'name': 'C', 'order': 1, 'active': true}),
      ]);
      await _show(tester, store, 'promotions');
      await tester.tap(find.byKey(const ValueKey('renumber')));
      await tester.pumpAndSettle();
      expect([for (final id in ['p1', 'p2', 'p3']) _order(store, 'promotions', id)], [1, 2, 3]);

      await _show(tester, store, 'categories');
      await tester.drag(find.byIcon(Icons.drag_indicator).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_order(store, 'categories', 'cat-care'), lessThan(_order(store, 'categories', 'cat-fruits')));
    });

    testWidgets('Products-only controls do not appear on other lists, and technical ids are hidden there too', (tester) async {
      final store = await _store();
      await _show(tester, store, 'shops');
      expect(find.byKey(const ValueKey('product-search')), findsNothing);
      expect(find.byKey(const ValueKey('toggle-select')), findsNothing);
      expect(find.textContaining('shop-a'), findsNothing);
      expect(find.text('Local Bakery'), findsOneWidget);
    });
  });
}
