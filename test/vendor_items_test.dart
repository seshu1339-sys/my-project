import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/vendor_items.dart';
import 'package:ecommerce_app/ui/admin_entry_list.dart';
import 'package:ecommerce_app/ui/vendor_section_products.dart';

/// Records the server calls (Store.call is the one place every call goes through).
class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'status': 'approved', 'docId': 'p1'};
  }
}

const _categories = [
  Entry('cat-veg', {'name': 'Vegetables', 'order': 1, 'active': true}),
  Entry('cat-kirana', {'name': 'Kirana', 'order': 2, 'active': true}),
  Entry('cat-empty', {'name': 'Plastic', 'order': 3, 'active': true}),
];
const _library = [
  Entry('lib-tomato', {'name': 'Tomato', 'categoryId': 'cat-veg', 'imageUrl': '', 'active': true, 'order': 1}),
  Entry('lib-onion', {'name': 'Onion', 'categoryId': 'cat-veg', 'imageUrl': '', 'active': true, 'order': 2}),
  Entry('lib-old', {'name': 'Old item', 'categoryId': 'cat-veg', 'imageUrl': '', 'active': false, 'order': 3}),
  Entry('lib-rice', {'name': 'Sona Masoori Rice', 'categoryId': 'cat-kirana', 'imageUrl': '', 'active': true, 'order': 1}),
  Entry('lib-misc', {'name': 'Candle', 'categoryId': '', 'imageUrl': '', 'active': true, 'order': 1}),
];

void main() {
  test('limits, quantities and the library by category', () {
    expect(vendorItemLimit(null), 2);
    expect(vendorItemLimit({'itemLimit': 5}), 5);
    expect(vendorItemLimit({'itemLimit': 0}), 0);
    expect(vendorItemLimit({'itemLimit': '5'}), 2);
    expect(vendorItemUnit('kg', 2), '2 kg');
    expect(vendorItemUnit('pcs', 1), '1 pc');
    expect(vendorItemUnit('pcs', 10), '10 pcs');
    expect(vendorItemQuantities, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(libraryItemsIn(_library, 'cat-veg').map((e) => e.id), ['lib-tomato', 'lib-onion'], reason: 'switched-off items are left out');
    expect(libraryCategories(_library, _categories), [('cat-veg', 'Vegetables'), ('cat-kirana', 'Kirana'), ('', 'Other items')], reason: 'only categories with items, then Other');
  });

  test('a vendor price lasts 24 hours, then the vendor sees it has expired', () {
    final now = DateTime.utc(2026, 10, 25, 9, 0);
    final fresh = {'price': 50, 'unit': '2 kg', 'priceExpiresAt': now.add(const Duration(hours: 23, minutes: 10)).toIso8601String()};
    expect(vendorPriceExpired(fresh, now), isFalse);
    expect(vendorPriceLine(fresh, now), '₹50 for 2 kg • valid for 23 h 10 min');
    final due = {...fresh, 'priceExpiresAt': now.subtract(const Duration(minutes: 1)).toIso8601String()};
    expect(vendorPriceExpired(due, now), isTrue, reason: 'past its 24 hours, even before the price is removed');
    expect(vendorPriceLine(due, now), 'Price expired: enter a new price');
    expect(vendorPriceExpired({'unit': '2 kg', 'priceExpired': true}, now), isTrue, reason: 'the price was removed');
    expect(vendorPriceLine({'price': 60, 'unit': '1 kg'}, now), '₹60 for 1 kg', reason: 'an item from before prices expired keeps showing its price');
    expect(vendorPriceValidHours, 24);
  });

  Future<_RecordingStore> pumpSection(WidgetTester tester, (int, int, bool) preview) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _RecordingStore();
    store.catalog['categories'] = _categories;
    store.catalog['productImageLibrary'] = _library;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VendorAddProductSection(store: store, uid: 'v1', preview: preview)))));
    return store;
  }

  testWidgets('a first item: category, then an admin item (no typing), Pieces 1-10, the price for that quantity, Save', (tester) async {
    final store = await pumpSection(tester, (0, 2, true));
    expect(find.text('Items: 0 of 2'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'nothing to type before an item is chosen');
    await tester.tap(find.byKey(const ValueKey('vendor-item-category-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetables').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vendor-library-item-lib-tomato')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-library-item-lib-old')), findsNothing);
    expect(find.byKey(const ValueKey('vendor-library-item-lib-rice')), findsNothing, reason: 'only the chosen category');
    await tester.tap(find.byKey(const ValueKey('vendor-library-item-lib-tomato')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pieces'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-item-quantity-pcs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 pcs').last);
    await tester.pumpAndSettle();
    expect(find.text('Price for 3 pcs (₹)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('vendor-item-price')), '90');
    await tester.tap(find.byKey(const ValueKey('vendor-item-save')));
    await tester.pumpAndSettle();
    expect(store.calls.single.$1, 'submitVendorChange');
    expect(store.calls.single.$2['changes'], {'libraryItemId': 'lib-tomato', 'unitType': 'pcs', 'quantity': 3, 'price': 90.0});
    expect(find.textContaining('live'), findsWidgets);
  });

  testWidgets('below the limit: "Add another item" opens the form; at the limit: no button, ask the admin', (tester) async {
    await pumpSection(tester, (1, 2, true));
    expect(find.text('Items: 1 of 2'), findsOneWidget);
    expect(find.text('Add another item'), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-item-category-null')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('vendor-add-another')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vendor-item-category-null')), findsOneWidget);

    await pumpSection(tester, (2, 2, true));
    expect(find.text('Items: 2 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-add-another')), findsNothing);
    expect(find.byKey(const ValueKey('vendor-item-limit-reached')), findsOneWidget);
  });

  testWidgets('without photo 1 of the shop nothing can be added', (tester) async {
    await pumpSection(tester, (1, 2, false));
    expect(find.byKey(const ValueKey('shop-photo-required')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('vendor-add-another'))).onPressed, isNull);
  });

  testWidgets('admin Products list: "Vendor items" shows only the items vendors added', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['products'] = const [
      Entry('p-admin', {'name': 'Admin rice', 'categoryId': 'cat-kirana', 'shopId': 's', 'order': 1, 'active': true, 'price': 50, 'stock': 5}),
      Entry('p-vendor', {'name': 'Vendor tomato', 'categoryId': 'cat-veg', 'shopId': 's', 'ownerId': 'v1', 'order': 2, 'active': false, 'price': 24, 'stock': 5}),
    ];
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminEntryList(store: store, section: 'products'))));
    await tester.pumpAndSettle();
    expect(find.text('Admin rice'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filter-vendor-items')));
    await tester.pumpAndSettle();
    expect(find.text('Admin rice'), findsNothing);
    expect(find.text('Vendor tomato'), findsOneWidget, reason: 'a hidden vendor item is listed too');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
