import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/customer_position.dart';
import 'package:ecommerce_app/ui/item_shop_list.dart';
import 'package:ecommerce_app/ui/product_page.dart';
import 'package:ecommerce_app/ui/shop_route_map.dart';

const _shops = [
  Entry('shopA', {'name': 'Lakshmi Kirana', 'latitude': 17.668, 'longitude': 82.612, 'phone': '9876511111', 'town': 'Narsipatnam', 'imageUrl': 'http://x/a.jpg'}),
  Entry('shopB', {'name': 'Ravi Fruits', 'latitude': 17.690, 'longitude': 82.640, 'phone': '9876522222', 'town': 'Narsipatnam'}),
];
const _products = [
  Entry('p1', {'name': 'Tomato', 'price': 32, 'unit': '1 kg', 'shopId': 'shopA', 'stock': 5, 'imageUrl': 'http://x/t.png'}),
  Entry('p2', {'name': 'Tomato', 'price': 28, 'unit': '1 kg', 'shopId': 'shopB', 'stock': 5}),
];

void main() {
  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['shops'] = [..._shops];
    store.catalog['products'] = [..._products];
    return store;
  }

  testWidgets('the item page: photo and price large, beside them every shop with its price and distance; a shop opens on the map', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final asks = <bool>[];
    CustomerPosition.finder = ({required bool ask}) async {
      asks.add(ask);
      return ask ? (latitude: 17.667, longitude: 82.611) : null;
    };
    addTearDown(CustomerPosition.reset);
    final store = await openStore();
    await tester.pumpWidget(MaterialApp(home: ProductPage(store: store, entry: _products.first)));
    await tester.pump();
    await tester.pump();
    expect(asks, [false, true], reason: 'asked once for the distance');
    expect(find.byKey(const ValueKey('product-price')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('product-price'))).style?.fontSize, greaterThanOrEqualTo(30));
    expect(find.text('Shops selling this (2)'), findsOneWidget);
    // beside the photo on a wide screen
    expect(tester.getTopLeft(find.byType(ItemShopList)).dx, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('product-price'))).dx + 200));
    expect(find.textContaining(RegExp(r'^₹28 for 1 kg • [\d.]+ km$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^₹32 for 1 kg • \d+ m$')), findsOneWidget);
    // still the item page's own buttons
    expect(find.byKey(const ValueKey('compare-shops')), findsOneWidget);
    expect(find.text('Add to bag'), findsOneWidget);

    await tester.tap(find.text('Ravi Fruits'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShopRouteView), findsOneWidget);
    expect(find.text('Phone: 9876522222'), findsOneWidget);
    expect(find.text('Tomato: ₹28 / 1 kg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no location given: the list without distances, and a button to turn it on', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CustomerPosition.finder = ({required bool ask}) async => null;
    addTearDown(CustomerPosition.reset);
    final store = await openStore();
    await tester.pumpWidget(MaterialApp(home: ProductPage(store: store, entry: _products.first)));
    await tester.pump();
    await tester.pump();
    expect(find.text('₹28 for 1 kg'), findsOneWidget);
    expect(find.text('₹32 for 1 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('item-shops-locate')), findsOneWidget);
    // on a phone the list is under the price
    expect(tester.getTopLeft(find.byType(ItemShopList)).dy, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('product-price'))).dy));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
