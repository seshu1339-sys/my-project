import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/item_shops.dart';
import 'package:ecommerce_app/domain/towns.dart';
import 'package:ecommerce_app/ui/item_shops_page.dart';

const _shops = [
  Entry('shopA', {'name': 'Lakshmi Kirana', 'latitude': 17.668, 'longitude': 82.612, 'address': 'Main Road, Narsipatnam', 'phone': '9876511111', 'town': 'Narsipatnam', 'active': true, 'imageUrl': 'http://x/a.jpg'}),
  Entry('shopB', {'name': 'Ravi Fruits', 'latitude': 17.672, 'longitude': 82.620, 'address': 'Bus Stand Road', 'phone': '9876522222', 'town': 'Narsipatnam', 'active': true}),
  Entry('shopC', {'name': 'Sai Vegetables', 'latitude': 17.660, 'longitude': 82.600, 'address': 'Market', 'town': 'Narsipatnam', 'active': true}),
];
const _products = [
  Entry('p1', {'name': 'Tomato', 'libraryItemId': 'lib-tomato', 'price': 32, 'unit': '1 kg', 'shopId': 'shopA', 'town': 'Narsipatnam', 'active': true}),
  Entry('p2', {'name': 'tomato ', 'libraryItemId': 'lib-tomato', 'price': 28, 'unit': '1 kg', 'shopId': 'shopB', 'town': 'Narsipatnam', 'active': true}),
  Entry('p3', {'name': 'Tomato', 'price': 30, 'unit': '1 kg', 'shopId': 'shopC', 'town': 'Narsipatnam', 'active': true}),
  // price ran out (24 hours): not offered
  Entry('p4', {'name': 'Tomato', 'libraryItemId': 'lib-tomato', 'priceExpired': true, 'shopId': 'shopC', 'town': 'Narsipatnam', 'active': true}),
  Entry('p5', {'name': 'Cherry Tomato', 'price': 80, 'unit': '1 kg', 'shopId': 'shopA', 'town': 'Narsipatnam', 'active': true}),
  Entry('p6', {'name': 'Onion', 'price': 40, 'unit': '1 kg', 'shopId': 'shopA', 'town': 'Narsipatnam', 'active': true}),
];

void main() {
  test('the items to choose from: one per item, with how many shops sell it and the lowest price', () {
    final choices = itemChoices(_products, 'tom');
    expect(choices.map((c) => c.name), ['Tomato', 'Cherry Tomato'], reason: 'starting with the word first');
    expect([choices.first.shops, choices.first.lowest, choices.first.libraryItemId], [3, 28, 'lib-tomato']);
    expect(itemChoices(_products, 'cherry tom').single.name, 'Cherry Tomato');
    expect(itemChoices(_products, ' '), isEmpty);
    expect(itemChoices(_products, 'potato'), isEmpty);
  });

  test('where to buy: every shop with a price for the item, cheapest first, with the distance from the customer', () {
    final offers = itemOffers(_products, _shops, name: 'Tomato', libraryItemId: 'lib-tomato', latitude: 17.667, longitude: 82.611);
    expect(offers.map((o) => [o.shopName, o.price]), [['Ravi Fruits', 28], ['Sai Vegetables', 30], ['Lakshmi Kirana', 32]]);
    expect(offers.every((o) => o.onMap), isTrue);
    expect(offers.last.distanceKm, closeTo(0.15, 0.05));
    expect(offers.last.photo, 'http://x/a.jpg');
    expect(offers.first.phone, '9876522222');
    expect(distanceText(offers.last.distanceKm), matches(RegExp(r'^\d+ m$')));
    expect(distanceText(2.345), '2.3 km');
    expect(distanceText(null), '');
    // the same price: the nearest first; a product without its shop still uses its own place
    final tie = itemOffers(const [
      Entry('x1', {'name': 'Rice', 'price': 50, 'shopId': 'far', 'latitude': 17.9, 'longitude': 82.9}),
      Entry('x2', {'name': 'Rice', 'price': 50, 'shopId': 'near', 'latitude': 17.668, 'longitude': 82.612}),
    ], const [], name: 'Rice', latitude: 17.667, longitude: 82.611);
    expect(tie.map((o) => o.product.id), ['x2', 'x1']);
    expect(isSameItem(const Entry('y', {'name': 'Desi Tomato', 'libraryItemId': 'lib-tomato'}), name: 'Tomato', libraryItemId: 'lib-tomato'), isTrue);
  });

  Future<Store> store() async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.init();
    s.catalog['shops'] = [..._shops];
    s.catalog['products'] = [..._products];
    await s.setLocation('531116', 'Narsipatnam', lat: 17.667, lng: 82.611);
    return s;
  }

  testWidgets('the page: a map pin per shop with its price, a list from the lowest price, and a shop\'s photo, address, phone and route', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await store();
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: ItemShopsPage(store: s, name: 'Tomato', libraryItemId: 'lib-tomato', openItem: (e) => opened.add(e.id))));
    await tester.pump();
    expect(find.text('3 shops near you • from ₹28'), findsOneWidget);
    for (final id in ['shopA', 'shopB', 'shopC']) {
      expect(find.byKey(ValueKey('item-pin-$id')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('item-pin-shopB')), matching: find.text('₹28')), findsOneWidget);
    final rows = [for (final i in [0, 1, 2]) tester.widget<ListTile>(find.descendant(of: find.byKey(ValueKey('item-offer-$i')), matching: find.byType(ListTile)))];
    expect(rows.map((r) => (r.title as Text).data), ['Ravi Fruits', 'Sai Vegetables', 'Lakshmi Kirana']);
    expect((rows.first.subtitle as Text).data, startsWith('₹28 for 1 kg • '));

    await tester.tap(find.byKey(const ValueKey('item-offer-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-shop-sheet')), findsOneWidget);
    expect(find.text('Tomato: ₹32 for 1 kg'), findsOneWidget);
    expect(find.text('Main Road, Narsipatnam'), findsOneWidget);
    expect(find.text('Phone: 9876511111'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.byKey(const ValueKey('item-shop-directions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('item-shop-open-item')));
    await tester.pumpAndSettle();
    expect(opened, ['p1']);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('a new shop or a new price shows at once (the catalogue is live)', (tester) async {
    final s = await store();
    await tester.pumpWidget(MaterialApp(home: ItemShopsPage(store: s, name: 'Onion', openItem: (_) {})));
    await tester.pump();
    expect(find.text('1 shop near you • from ₹40'), findsOneWidget);
    s.catalog['products'] = [..._products, const Entry('p7', {'name': 'Onion', 'price': 35, 'unit': '1 kg', 'shopId': 'shopB', 'town': 'Narsipatnam', 'active': true})];
    s.notifyListeners();
    await tester.pump();
    expect(find.text('2 shops near you • from ₹35'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  test('a customer located in a locality named with its town in brackets sees the town\'s shops', () async {
    expect(townKey('Krishna Bazar (Narsipatnam)'), 'narsipatnam');
    expect(townKey(' Narsipatnam '), 'narsipatnam');
    expect(townKey('Tuni'), 'tuni');
    final s = await store();
    await s.setLocation('531118', 'Krishna Bazar (Narsipatnam)', lat: 17.667, lng: 82.611, town: 'Krishna Bazar (Narsipatnam)');
    expect(itemOffers(s.visibleProducts(), s.visible('shops'), name: 'Tomato').length, 3);
    await s.setLocation('533401', 'Tuni', town: 'Tuni');
    expect(itemOffers(s.visibleProducts(), s.visible('shops'), name: 'Tomato'), isEmpty, reason: 'another town');
    s.dispose();
  });

  testWidgets('typing an item shows what to choose; choosing opens where to buy it', (tester) async {
    final s = await store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ItemSearchChoices(store: s, query: 'tom', openItem: (_) {}))));
    expect(find.text('Tomato • 3 shops • from ₹28'), findsOneWidget);
    expect(find.text('Cherry Tomato • 1 shop • from ₹80'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('item-choice-tomato')));
    await tester.pumpAndSettle();
    expect(find.text('Where to buy Tomato'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
